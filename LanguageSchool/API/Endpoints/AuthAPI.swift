import Foundation

// MARK: - DTOs

struct TokenPairDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let isNewUser: Bool?
    /// Серверный документ юзера. Возвращается ВМЕСТЕ с токенами на
    /// login-эндпоинтах (`/auth/dev`, `/auth/apple`, `/auth/google`).
    /// На refresh — отсутствует.
    let user: MeDTO?
}

// MARK: - Endpoints

@MainActor
enum AuthAPI {

    /// Логин по Apple `identityToken` (JWT из ASAuthorizationAppleIDCredential).
    static func loginApple(
        identityToken: String,
        authorizationCode: String? = nil,
        fullName: String? = nil,
        email: String? = nil
    ) async throws -> TokenPairDTO {
        struct Body: Encodable {
            let identityToken: String
            let authorizationCode: String?
            let fullName: String?
            let email: String?
        }
        return try await APIClient.shared.send(
            .POST, "/v1/auth/apple",
            body: Body(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                email: email
            ),
            authorized: false
        )
    }

    /// Логин по Google `idToken` (из GIDGoogleUser.idToken).
    static func loginGoogle(idToken: String) async throws -> TokenPairDTO {
        struct Body: Encodable { let idToken: String }
        return try await APIClient.shared.send(
            .POST, "/v1/auth/google",
            body: Body(idToken: idToken),
            authorized: false
        )
    }

    /// Dev-логин по email. Работает только на стенде (`ENV != production`).
    static func loginDev(email: String) async throws -> TokenPairDTO {
        struct Body: Encodable { let email: String }
        return try await APIClient.shared.send(
            .POST, "/v1/auth/dev",
            body: Body(email: email),
            authorized: false
        )
    }

    /// Обмен refresh-токена на новую пару. Обычно клиенту звать не нужно —
    /// APIClient делает это автоматически на 401. Оставлено для явных
    /// сценариев (например, warm-up после долгой паузы).
    static func refresh(refreshToken: String) async throws -> TokenPairDTO {
        struct Body: Encodable { let refreshToken: String }
        return try await APIClient.shared.send(
            .POST, "/v1/auth/refresh",
            body: Body(refreshToken: refreshToken),
            authorized: false
        )
    }

    /// Отзыв всех refresh-токенов текущего юзера. После — clear TokenStore.
    static func logout() async throws {
        _ = try await APIClient.shared.send(.POST, "/v1/auth/logout")
    }
}
