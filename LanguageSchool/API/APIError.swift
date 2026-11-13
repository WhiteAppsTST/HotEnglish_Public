import Foundation

/// Ошибка API согласованная с сервером `Tutor API`. Тело сервера всегда одной
/// формы `{"error": {"code": "...", "message": "..."}}`; кроме того, есть
/// типовые статусы, которые UI обрабатывает отдельно.
enum APIError: Error, LocalizedError {

    /// 401 — access-токен истёк / невалиден. Клиент должен обновить через
    /// `/v1/auth/refresh` и повторить запрос. Внутрь этой ошибки летит после
    /// провала refresh-а (не осталось валидного refresh-токена).
    case unauthorized

    /// 402 — премиум обязателен, показываем пейволл.
    case paymentRequired(code: String?, message: String?)

    /// 403 — чужой userId в пути. Ошибка клиента.
    case forbidden(code: String?, message: String?)

    /// 409 — шаг закрыт / попытка уже завершена. Клиент должен перечитать
    /// прогресс из тела ответа.
    case conflict(code: String?, message: String?)

    /// 429 — дневная квота исчерпана. `resetsAt` — когда обновится.
    case rateLimited(code: String?, message: String?, resetsAt: Date?)

    /// Прочие HTTP-ошибки (4xx/5xx) с распарсенным телом.
    case http(status: Int, code: String?, message: String?)

    /// Ошибка транспорта — сеть, DNS, TLS, тайм-аут. Оборачивает URLError.
    case transport(URLError)

    /// Декодер сломался на теле ответа сервера.
    case decoding(Error)

    /// URL или тело запроса собраны некорректно на клиенте.
    case badRequestConstruction

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .paymentRequired(_, let msg),
             .forbidden(_, let msg),
             .conflict(_, let msg),
             .rateLimited(_, let msg, _):
            return msg ?? "Request refused."
        case .http(let s, _, let msg):
            return msg ?? "Server error (\(s))."
        case .transport(let e):
            return e.localizedDescription
        case .decoding:
            return "Unexpected response from the server."
        case .badRequestConstruction:
            return "Failed to build the request."
        }
    }
}

/// Тело ошибки сервера. Свободный `code` для диагностики.
struct APIErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let code: String?
        let message: String?
    }
    let error: Inner
}
