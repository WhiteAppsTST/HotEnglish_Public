import Foundation

// MARK: - Public models

nonisolated
struct AIMessage: Hashable, Sendable, Identifiable, Codable {
    enum Role: String, Sendable, Codable {
        case user
        case assistant
    }
    let id: String
    let role: Role
    let text: String
    let createdAt: Date
}

// MARK: - Audio input/output

/// Аудио-инпут от пользователя. Отсылается в OpenAI как base64-строка.
nonisolated
struct AIAudioInput: Sendable {
    enum Format: String, Sendable { case wav, mp3 }
    let data: Data
    let format: Format
}

/// Аудио-ответ Emma. `data` — raw байты в формате, который просили в
/// `AIReplyModality.textAndAudio(format:)`. Плеер (AVAudioPlayer) сам разберёт.
nonisolated
struct AIAudioOutput: Sendable {
    let data: Data
    let format: String
    let voice: String
}

/// Модальность ответа. `textOnly` — обычный текстовый ответ (дефолт).
/// `textAndAudio` — Emma отвечает и голосом, и текстом (transcript возвращается
/// как `AIReply.message.text`, аудио — как `AIReply.audio`).
nonisolated
enum AIReplyModality: Sendable {
    case textOnly
    case textAndAudio(voice: String = "alloy", format: String = "wav")
}

/// Обёртка над ответом мультимодального метода. Для `textOnly` `audio == nil`.
nonisolated
struct AIReply: Sendable {
    let message: AIMessage
    let audio: AIAudioOutput?
}

// MARK: - Errors

nonisolated
enum AIChatError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case network(String)
    case http(Int, String?)
    case decode(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:       "OPENAI_API_KEY missing in Info.plist"
        case .network(let s):      "Network error: \(s)"
        case .http(let code, let body): "HTTP \(code)\(body.map { " — \($0.prefix(200))" } ?? "")"
        case .decode(let s):       "Decode error: \(s)"
        case .badResponse:         "Bad response shape"
        }
    }
}

// MARK: - Service

protocol AIChatServicing: Sendable {
    /// Stateless-запрос: клиент шлёт system-prompt + всю историю (user/assistant пары)
    /// в порядке созревания, получает следующее сообщение ассистента.
    /// Использовать для обычного текстового чата с дешёвой моделью.
    func send(
        history: [AIMessage],
        systemPrompt: String,
        model: String
    ) async throws -> AIMessage

    /// Talk-вариант: то же что `send`, но принуждает модель отвечать JSON'ом
    /// `{"text": ..., "reaction": ...}` (см. `TalkReaction`) через OpenAI
    /// `response_format: json_object`. Возвращает распарсенный tuple. Если
    /// JSON пришёл сломанным — reaction=nil, весь content идёт как text.
    func sendWithReaction(
        history: [AIMessage],
        systemPrompt: String,
        model: String
    ) async throws -> (message: AIMessage, reaction: TalkReaction?)

    /// Мультимодальный вариант: user может добавить аудио-инпут (запись голоса)
    /// и/или попросить Emma ответить голосом. Требует audio-capable модель
    /// (`AIChatService.audioModel`). Используется для Speaking-степов и будущего
    /// голосового режима Talk.
    ///
    /// - Parameters:
    ///   - history: предыдущие текстовые реплики (audio в истории не храним).
    ///   - userAudio: если задано — добавляется как новая user-реплика с аудио.
    ///     Если `nil`, модель отвечает только на историю (полезно для text-in /
    ///     audio-out когда хотим голос от Emma на текстовый ввод).
    ///   - replyModality: `.textOnly` (дефолт) или `.textAndAudio`.
    func sendMultimodal(
        history: [AIMessage],
        userAudio: AIAudioInput?,
        systemPrompt: String,
        model: String,
        replyModality: AIReplyModality
    ) async throws -> AIReply
}

actor AIChatService: AIChatServicing {

    // MARK: - Config

    /// Дешёвая text-only модель для обычного Talk-чата.
    nonisolated static let defaultModel = "gpt-4o-mini"

    /// Audio-capable модель. Понимает аудио на вход, умеет отвечать голосом.
    /// Самый дешёвый tier с этой возможностью.
    nonisolated static let audioModel = "gpt-4o-mini-audio-preview"

    nonisolated private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private let session: URLSession
    private let apiKey: String

    init(session: URLSession = .shared) throws {
        self.session = session
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
            !key.isEmpty,
            key != "PUT_YOUR_KEY_HERE"
        else {
            throw AIChatError.missingAPIKey
        }
        self.apiKey = key
    }

    // MARK: - Public

    func send(
        history: [AIMessage],
        systemPrompt: String,
        model: String = defaultModel
    ) async throws -> AIMessage {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: history.map {
            ["role": $0.role.rawValue, "content": $0.text]
        })

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIChatError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)
            throw AIChatError.http(http.statusCode, bodyText)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let messageJSON = first["message"] as? [String: Any],
            let content = messageJSON["content"] as? String
        else {
            throw AIChatError.badResponse
        }

        return AIMessage(
            id: (json["id"] as? String) ?? UUID().uuidString,
            role: .assistant,
            text: content,
            createdAt: .now
        )
    }

    // MARK: - Send with reaction (JSON mode)

    func sendWithReaction(
        history: [AIMessage],
        systemPrompt: String,
        model: String = defaultModel
    ) async throws -> (message: AIMessage, reaction: TalkReaction?) {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: history.map {
            ["role": $0.role.rawValue, "content": $0.text]
        })

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIChatError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIChatError.http(http.statusCode, String(data: data, encoding: .utf8))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let messageJSON = first["message"] as? [String: Any],
            let content = messageJSON["content"] as? String
        else {
            throw AIChatError.badResponse
        }

        // Парсим внутренний JSON. Если сломан — считаем весь content'ом как text.
        var text = content
        var reaction: TalkReaction? = nil
        if let inner = content.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: inner) as? [String: Any] {
            if let t = parsed["text"] as? String, !t.isEmpty {
                text = t
            }
            if let rawReaction = parsed["reaction"] as? String {
                reaction = TalkReaction(rawValue: rawReaction.lowercased())
            }
        }

        let message = AIMessage(
            id: (json["id"] as? String) ?? UUID().uuidString,
            role: .assistant,
            text: text,
            createdAt: .now
        )
        return (message, reaction)
    }

    // MARK: - Multimodal (audio in/out)

    func sendMultimodal(
        history: [AIMessage],
        userAudio: AIAudioInput?,
        systemPrompt: String,
        model: String = audioModel,
        replyModality: AIReplyModality = .textOnly
    ) async throws -> AIReply {

        // 1. Собираем messages: system + история + опционально user-turn с аудио.
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: history.map {
            ["role": $0.role.rawValue, "content": $0.text]
        })
        if let userAudio {
            apiMessages.append([
                "role": "user",
                "content": [
                    [
                        "type": "input_audio",
                        "input_audio": [
                            "data": userAudio.data.base64EncodedString(),
                            "format": userAudio.format.rawValue
                        ]
                    ]
                ]
            ])
        }

        // 2. Payload с modalities/audio-параметрами.
        var payload: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]
        switch replyModality {
        case .textOnly:
            payload["modalities"] = ["text"]
        case .textAndAudio(let voice, let format):
            payload["modalities"] = ["text", "audio"]
            payload["audio"] = ["voice": voice, "format": format]
        }

        // 3. Send.
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIChatError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)
            throw AIChatError.http(http.statusCode, bodyText)
        }

        // 4. Разбор ответа.
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let messageJSON = first["message"] as? [String: Any]
        else {
            throw AIChatError.badResponse
        }

        // Текст: при text+audio лежит в `audio.transcript`, при text-only — в `content`.
        let text: String
        var audioOut: AIAudioOutput? = nil
        if let audioJSON = messageJSON["audio"] as? [String: Any] {
            let transcript = (audioJSON["transcript"] as? String) ?? ""
            text = transcript
            if let b64 = audioJSON["data"] as? String, let bytes = Data(base64Encoded: b64) {
                let format: String = {
                    if case .textAndAudio(_, let f) = replyModality { return f }
                    return "wav"
                }()
                let voice: String = {
                    if case .textAndAudio(let v, _) = replyModality { return v }
                    return "alloy"
                }()
                audioOut = AIAudioOutput(data: bytes, format: format, voice: voice)
            }
        } else if let content = messageJSON["content"] as? String {
            text = content
        } else {
            throw AIChatError.badResponse
        }

        let message = AIMessage(
            id: (json["id"] as? String) ?? UUID().uuidString,
            role: .assistant,
            text: text,
            createdAt: .now
        )
        return AIReply(message: message, audio: audioOut)
    }
}
