import SwiftUI
import GoogleSignIn
import AuthenticationServices

// MARK: - Public model
nonisolated
enum AuthProvider: String, Codable, Hashable, Sendable {
    case google, apple
}

struct AuthUser: Hashable {
    let id: String
    let email: String?
    let name: String?
    let profileImageUrl: URL?
    let provider: AuthProvider
}

enum AuthError: LocalizedError {
    case invalidCredential
    case noPresenter
    case cancelled
    case backend(APIError)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Invalid credential"
        case .noPresenter:       "No presenting view controller"
        case .cancelled:         "Sign in cancelled"
        case .backend(let e):    e.localizedDescription
        case .underlying(let e): e.localizedDescription
        }
    }
}

/// Локальный сырой результат от Apple — до похода на бэк.
private struct AppleCredentialPayload {
    let userId: String
    let identityToken: String
    let authorizationCode: String?
    let fullName: String?
    let email: String?
}

// MARK: - Service (singleton)

@MainActor
@Observable
final class AuthService: NSObject {

    static let shared = AuthService()

    var currentUser: AuthUser?
    /// Свежий серверный документ юзера. `nil` пока не подтянули (или до логина).
    /// Обновляется после логина, restore и явного `syncMe()`.
    var currentMe: MeDTO?
    /// Тикает на КАЖДЫЙ успешный syncMe (даже когда id/updatedAt не поменялись
    /// — сервер такое умеет: `user.updatedAt` статичный, а вложенные
    /// `streak/learningProfiles/teacherRelationships` обновляются). RootView
    /// слушает и дёргает `hydrateUser()` → `MeMapper.upsert` → зеркалит новую
    /// прогрессию в SwiftData → UI перерисовывается. Без нонса onChange по
    /// `.id` не тригерился и completedStepIds оставались пустыми.
    var meSyncNonce: Int = 0
    var errorMessage: String?
    var isBusy: Bool = false
    /// `true` пока идёт `restore()` при холодном старте (валидируем токены
    /// через GET /me, если refresh не протух). RootView в это время держит
    /// сплэш вместо AuthGate — иначе юзер видит AuthGate на долю секунды
    /// и по инерции жмёт Sign-In, создавая новую сессию поверх валидной.
    var isRestoring: Bool = true

    var isLoggedIn: Bool { currentUser != nil }

    private var appleContinuation: CheckedContinuation<AppleCredentialPayload, Error>?

    private override init() {
        super.init()
        Task { await restore() }
    }

    // MARK: - Setup
    static func configure(googleClientID: String) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
    }

    // MARK: - Google
    func signInWithGoogle() async {
        guard let presenter = Self.topViewController() else {
            errorMessage = AuthError.noPresenter.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = AuthError.invalidCredential.localizedDescription
                return
            }
            let pair = try await AuthAPI.loginGoogle(idToken: idToken)
            TokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
            applyBackendSession(googleUser: result.user)
            // Если сервер вернул user в теле — сразу зеркалим (иначе на
            // hydrateUser промелькнёт скелет с externalAuthId=googleUserID
            // и Onboarding вспыхнет).
            if let me = pair.user {
                currentMe = me
                meSyncNonce &+= 1
            } else {
                await syncMe()
            }
            errorMessage = nil
        } catch let api as APIError {
            errorMessage = api.localizedDescription
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple
    func signInWithApple() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let payload = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AppleCredentialPayload, Error>) in
                appleContinuation = cont
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName, .email]
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
            let pair = try await AuthAPI.loginApple(
                identityToken: payload.identityToken,
                authorizationCode: payload.authorizationCode,
                fullName: payload.fullName,
                email: payload.email
            )
            TokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
            KeychainStore.set(payload.userId, for: .appleUserIdentifier)
            // Сначала пробуем взять юзера из ответа /auth/apple (сервер его
            // кладёт в тело) — тогда AuthUser.id = серверный uuid и hydrateUser
            // сразу найдёт правильный UserEntity вместо создания скелета
            // с externalAuthId=payload.userId → Onboarding-flash + orphan.
            if let me = pair.user {
                currentMe = me
                meSyncNonce &+= 1
                currentUser = AuthUser(
                    id: me.id,
                    email: me.email ?? payload.email,
                    name: me.name ?? payload.fullName,
                    profileImageUrl: me.avatarUrl.flatMap(URL.init(string:)),
                    provider: .apple
                )
            } else {
                currentUser = AuthUser(
                    id: payload.userId,
                    email: payload.email,
                    name: payload.fullName,
                    profileImageUrl: nil,
                    provider: .apple
                )
                await syncMe()
            }
            errorMessage = nil
        } catch let api as APIError {
            errorMessage = api.localizedDescription
        } catch {
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    /// SignInWithAppleButton вызывает старый onCompletion(result:) — оставляем
    /// его как обёртку над новым flow: только достаём payload и уходим в
    /// standard бэкенд-цикл.
    func handleApple(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let payload = Self.payload(from: authorization) else {
                errorMessage = AuthError.invalidCredential.localizedDescription
                return
            }
            isBusy = true
            defer { isBusy = false }
            do {
                let pair = try await AuthAPI.loginApple(
                    identityToken: payload.identityToken,
                    authorizationCode: payload.authorizationCode,
                    fullName: payload.fullName,
                    email: payload.email
                )
                TokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
                KeychainStore.set(payload.userId, for: .appleUserIdentifier)
                currentUser = AuthUser(
                    id: payload.userId,
                    email: payload.email,
                    name: payload.fullName,
                    profileImageUrl: nil,
                    provider: .apple
                )
                await syncMe()
                errorMessage = nil
            } catch {
                errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Dev-логин (только стенд). Удобно для отладки без Apple/Google.
    func signInDev(email: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let pair = try await AuthAPI.loginDev(email: email)
            TokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
            applyLoginResponse(pair: pair, provider: .apple, fallbackEmail: email)
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Общая обёртка на login-ответ: если сервер положил `user` в тело —
    /// сразу зеркалим MeDTO и ставим AuthUser с СЕРВЕРНЫМ id (нельзя
    /// делать AuthUser с email/appleUserId — RootView.hydrateUser создаст
    /// СКЕЛЕТ-UserEntity с externalAuthId=email, вспыхнет Onboarding,
    /// и в SwiftData останется мёртвый второй UserEntity). Если сервер
    /// вдруг не прислал user (старый бэк) — fallback на syncMe().
    private func applyLoginResponse(
        pair: TokenPairDTO,
        provider: AuthProvider,
        fallbackEmail: String? = nil
    ) {
        if let me = pair.user {
            currentMe = me
            meSyncNonce &+= 1
            currentUser = AuthUser(
                id: me.id,
                email: me.email ?? fallbackEmail,
                name: me.name,
                profileImageUrl: me.avatarUrl.flatMap(URL.init(string:)),
                provider: provider
            )
        } else {
            Task { await syncMe() }
        }
    }

    /// Явный ресинк с сервером. RootView зовёт при появлении Home.
    @discardableResult
    func syncMe() async -> MeDTO? {
        do {
            let me = try await MeAPI.me()
            currentMe = me
            meSyncNonce &+= 1
            return me
        } catch APIError.unauthorized {
            finalizeSignOut()
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Restore & sign out

    /// Восстановление сессии на старте приложения. Если в Keychain лежат оба
    /// токена — валидируем их через `GET /v1/me`. Если сервер отдал 401
    /// (refresh протух) — чистим Keychain и уходим в AuthGate.
    ///
    /// Побочно синхронизируем Google SDK (для повторных scopes) — но серверная
    /// сессия остаётся авторитетной независимо от результата Google restore.
    func restore() async {
        defer { isRestoring = false }
        guard TokenStore.hasSession else {
            currentUser = nil
            return
        }
        // Валидация серверной сессии. APIClient сам сделает refresh при 401 на
        // /me; если и refresh не прошёл — вылетит APIError.unauthorized.
        do {
            let me = try await MeAPI.me()
            currentMe = me
            meSyncNonce &+= 1
            currentUser = AuthUser(
                id: me.id,
                email: me.email,
                name: me.name,
                profileImageUrl: me.avatarUrl.flatMap(URL.init(string:)),
                provider: KeychainStore.get(.appleUserIdentifier) != nil ? .apple : .google
            )
        } catch APIError.unauthorized {
            finalizeSignOut()
            return
        } catch {
            // Сеть/декодер сломались — не выкидываем юзера из сессии, пусть
            // попробует ещё раз через первый реальный запрос.
        }

        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
        }
    }

    /// Выход. Мгновенно скрываем UI юзера (currentUser=nil), но оставляем
    /// токены на время фонового `POST /auth/logout` + `DELETE /me/devices/{token}`
    /// — иначе оба запроса вернут 401. Только после этих двух вызовов
    /// финализируем очистку Keychain.
    func signOut() {
        let hadSession = currentUser != nil
        currentUser = nil
        currentMe = nil
        errorMessage = nil
        guard hadSession else {
            finalizeSignOut()
            return
        }
        Task {
            try? await AuthAPI.logout()
            await PushTokenService.shared.unregisterCurrent()
            finalizeSignOut()
        }
    }

    /// Удаление аккаунта (App Store требование). Сервер вычищает данные,
    /// потом обнуляем токены и локальную сессию.
    func deleteAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await MeAPI.deleteAccount()
            finalizeSignOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finalizeSignOut() {
        GIDSignIn.sharedInstance.signOut()
        TokenStore.clear()
        KeychainStore.remove(.appleUserIdentifier)
        currentUser = nil
        currentMe = nil
        errorMessage = nil
    }

    // MARK: - Private helpers

    private func applyBackendSession(googleUser: GIDGoogleUser) {
        let profile = googleUser.profile
        currentUser = AuthUser(
            id: googleUser.userID ?? UUID().uuidString,
            email: profile?.email,
            name: profile?.givenName,
            profileImageUrl: profile?.imageURL(withDimension: 100),
            provider: .google
        )
    }

    private static func payload(from authorization: ASAuthorization) -> AppleCredentialPayload? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else { return nil }
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        return AppleCredentialPayload(
            userId: credential.user,
            identityToken: identityToken,
            authorizationCode: code,
            fullName: fullName.isEmpty ? nil : fullName,
            email: credential.email
        )
    }

    private static func topViewController() -> UIViewController? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first(where: \.isKeyWindow)?
            .rootViewController
    }
}

// MARK: - Apple delegate

extension AuthService: ASAuthorizationControllerDelegate,
                       ASAuthorizationControllerPresentationContextProviding {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let payload = Self.payload(from: authorization) else {
                self.appleContinuation?.resume(throwing: AuthError.invalidCredential)
                self.appleContinuation = nil
                return
            }
            self.appleContinuation?.resume(returning: payload)
            self.appleContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleContinuation?.resume(throwing: error)
            self.appleContinuation = nil
        }
    }

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                .windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
