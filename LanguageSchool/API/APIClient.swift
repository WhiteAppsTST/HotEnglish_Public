import Foundation
import UIKit

/// HTTP-глагол. Не Codable — служебный тип.
enum HTTPMethod: String, Sendable {
    case GET, POST, PATCH, DELETE, PUT
}

/// Гибкий ISO8601-декодер: сервер может слать `...Z` и `...123Z` (с
/// миллисекундами) вперемешку — штатный `.iso8601` не понимает fractional
/// seconds, поэтому пробуем оба формата и падаем с внятной ошибкой.
enum APIDateCoders {
    static let iso8601FS: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Сервер шлёт `lastActiveDay` в формате "yyyy-MM-dd" (без времени и
    /// таймзоны) — ISO8601 такой формат не парсит. Без этого фолбэка вся
    /// `MeDTO` не декодится, `restore()` молча падает и юзер каждый раз
    /// попадает на AuthGate.
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let decodeStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let d = iso8601FS.date(from: raw) { return d }
        if let d = iso8601.date(from: raw) { return d }
        if let d = dateOnly.date(from: raw) { return d }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO8601 or yyyy-MM-dd date, got \(raw)"
        )
    }

    static let encodeStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(iso8601FS.string(from: date))
    }
}

/// Единая точка выхода к серверу Tutor API.
///
/// Отвечает за: сборку URL от базы, JSON-энкод/декод в snake→camel (сервер
/// уже отдаёт camelCase, но декодер терпимый), Bearer-инъекцию, автоматический
/// refresh на `401`, маппинг статусов → `APIError`.
///
/// Работает как @MainActor-изолированный singleton, чтобы refresh-цикл был
/// сериализован (один запрос обновляет пару токенов, остальные ждут его
/// результата) — иначе гонка двух 401'ов может выпалить два refresh-а сразу и
/// один из них словит invalid_grant.
@MainActor
final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Текущий in-flight refresh — все параллельные 401'ы ждут его.
    private var refreshTask: Task<Void, Error>?

    /// Собранный на init default User-Agent. Формируется один раз чтобы не
    /// дёргать Bundle/UIDevice на каждый запрос.
    let defaultUserAgent: String

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        let e = JSONEncoder()
        e.dateEncodingStrategy = APIDateCoders.encodeStrategy
        self.encoder = e

        let d = JSONDecoder()
        d.dateDecodingStrategy = APIDateCoders.decodeStrategy
        self.decoder = d

        let bundle = Bundle.main.infoDictionary ?? [:]
        let bundleId = bundle["CFBundleIdentifier"] as? String ?? "app"
        let version = bundle["CFBundleShortVersionString"] as? String ?? "0"
        let build = bundle["CFBundleVersion"] as? String ?? "0"
        let device = UIDevice.current
        self.defaultUserAgent = "LanguageSchool/\(version) (\(bundleId); build \(build); iOS \(device.systemVersion))"
    }

    // MARK: - Public API

    /// Основной метод — отправить запрос с телом и получить декодированный ответ.
    func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [String: String] = [:],
        extraHeaders: [String: String] = [:],
        authorized: Bool = true,
        as: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await sendRaw(
            method,
            path,
            body: body,
            query: query,
            extraHeaders: extraHeaders,
            authorized: authorized
        ).data
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // Печатаем подробную ошибку декодера. Молча заглушённый
            // decoding-error раньше приводил к тому, что restore() ронял
            // MeDTO и юзер прыгал на AuthGate без единой строки в консоли.
            print("[API] ✗ decode \(Response.self): \(error)")
            throw APIError.decoding(error)
        }
    }

    /// Отправить без ожидания тела ответа.
    @discardableResult
    func send(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [String: String] = [:],
        extraHeaders: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> HTTPURLResponse {
        try await sendRaw(
            method,
            path,
            body: body,
            query: query,
            extraHeaders: extraHeaders,
            authorized: authorized
        ).response
    }

    /// Возвращает и данные и ответ — для эндпоинтов с ETag.
    struct RawResult {
        let data: Data
        let response: HTTPURLResponse
    }

    func sendRaw(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [String: String] = [:],
        extraHeaders: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> RawResult {
        let request = try buildRequest(
            method: method,
            path: path,
            body: body,
            query: query,
            extraHeaders: extraHeaders,
            authorized: authorized
        )
        do {
            return try await execute(request, authorized: authorized, allowRefresh: true)
        } catch let apiError as APIError {
            throw apiError
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        }
    }

    // MARK: - Private: build + execute

    private func buildRequest(
        method: HTTPMethod,
        path: String,
        body: (any Encodable)?,
        query: [String: String],
        extraHeaders: [String: String],
        authorized: Bool
    ) throws -> URLRequest {
        var comps = URLComponents(
            url: AppConstants.API.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw APIError.badRequestConstruction }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.badRequestConstruction
            }
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if authorized, let token = TokenStore.access {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func execute(
        _ request: URLRequest,
        authorized: Bool,
        allowRefresh: Bool
    ) async throws -> RawResult {
        #if DEBUG
        if let body = request.httpBody, let s = String(data: body, encoding: .utf8) {
            print("[API] → \(request.httpMethod ?? "?") \(request.url?.path ?? "?")  body=\(s.prefix(400))")
        } else {
            print("[API] → \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
        }
        #endif
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badRequestConstruction
        }
        #if DEBUG
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            let tag = (200..<300).contains(http.statusCode) ? "✓" : "✗"
            print("[API] ← \(tag) \(http.statusCode) \(request.url?.path ?? "?")  body=\(s.prefix(3000))")
        } else {
            print("[API] ← \(http.statusCode) \(request.url?.path ?? "?")  <empty body>")
        }
        #endif

        switch http.statusCode {
        case 200..<300:
            return RawResult(data: data, response: http)

        case 401 where authorized && allowRefresh:
            try await refreshTokensSerial()
            var retry = request
            if let token = TokenStore.access {
                retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await execute(retry, authorized: true, allowRefresh: false)

        case 401:
            throw APIError.unauthorized

        default:
            throw mapError(status: http.statusCode, data: data, response: http)
        }
    }

    private func mapError(status: Int, data: Data, response: HTTPURLResponse) -> APIError {
        let env = try? decoder.decode(APIErrorEnvelope.self, from: data)
        let code = env?.error.code
        let msg = env?.error.message

        switch status {
        case 402: return .paymentRequired(code: code, message: msg)
        case 403: return .forbidden(code: code, message: msg)
        case 409: return .conflict(code: code, message: msg)
        case 429:
            let resetsAt = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap(TimeInterval.init)
                .map { Date(timeIntervalSince1970: $0) }
            return .rateLimited(code: code, message: msg, resetsAt: resetsAt)
        default:
            return .http(status: status, code: code, message: msg)
        }
    }

    // MARK: - Refresh

    /// Один параллельный refresh. Все 401'ы, попавшие в окно, ждут его результата.
    private func refreshTokensSerial() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            defer { self?.refreshTask = nil }
            try await self?.performRefresh()
        }
        refreshTask = task
        try await task.value
    }

    private func performRefresh() async throws {
        guard let refresh = TokenStore.refresh else {
            #if DEBUG
            print("[API] ⟲ refresh SKIPPED — no refreshToken in Keychain")
            #endif
            TokenStore.clear()
            throw APIError.unauthorized
        }
        struct Body: Encodable { let refreshToken: String }
        let request = try buildRequest(
            method: .POST,
            path: "/v1/auth/refresh",
            body: Body(refreshToken: refresh),
            query: [:],
            extraHeaders: [:],
            authorized: false
        )
        #if DEBUG
        print("[API] ⟲ POST /v1/auth/refresh (refresh token \(refresh.prefix(6))…)")
        #endif
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            #if DEBUG
            let status = http?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            print("[API] ⟲ ← \(status) /v1/auth/refresh  body=\(body)")
            #endif
            guard let http, (200..<300).contains(http.statusCode) else {
                TokenStore.clear()
                throw APIError.unauthorized
            }
            let dto = try decoder.decode(TokenPairDTO.self, from: data)
            TokenStore.save(access: dto.accessToken, refresh: dto.refreshToken)
            #if DEBUG
            print("[API] ⟲ refresh OK — tokens saved")
            #endif
        } catch {
            #if DEBUG
            print("[API] ⟲ refresh FAILED: \(error)")
            #endif
            TokenStore.clear()
            throw APIError.unauthorized
        }
    }
}

// MARK: - Helper types

/// Пустой ответ — для эндпоинтов, отдающих `204 No Content` / пустое тело.
struct EmptyResponse: Decodable {}

/// Erased Encodable — чтобы `body: any Encodable` попал в JSONEncoder.
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
