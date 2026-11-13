import Foundation
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {

    let user: UserEntity
    private let repository: UserRepository
    private let context: ModelContext

    /// Локализованная ошибка синка с сервером. Триггерит alert в view; view
    /// сбрасывает её в nil по кнопке OK.
    var syncError: String?

    init(user: UserEntity, repository: UserRepository, context: ModelContext) {
        self.user = user
        self.repository = repository
        self.context = context
    }

    // MARK: - Learning

    var currentLanguage: LanguageCode {
        get { user.settings.currentLearningLanguage }
        set {
            guard user.settings.currentLearningLanguage != newValue else { return }
            user.settings.currentLearningLanguage = newValue
            touch()
            syncSettings { $0.currentLearningLanguage = newValue.rawValue }
        }
    }

    var currentLevel: LangGrade {
        get { user.activeLearningProfile?.level ?? .aOne }
        set {
            guard let profile = user.activeLearningProfile, profile.level != newValue else { return }
            profile.level = newValue
            profile.updatedAt = .now
            touch()
            syncLearningProfile(profile) { $0.level = newValue.rawValue }
        }
    }

    var currentGoal: LearningGoal {
        get { user.activeLearningProfile?.goal ?? .somethingElse }
        set {
            guard let profile = user.activeLearningProfile, profile.goal != newValue else { return }
            profile.goal = newValue
            profile.updatedAt = .now
            touch()
            syncLearningProfile(profile) { $0.goal = newValue.rawValue }
        }
    }

    var dailyGoalMinutes: Int {
        get { user.settings.dailyGoalMinutes }
        set {
            guard user.settings.dailyGoalMinutes != newValue else { return }
            user.settings.dailyGoalMinutes = newValue
            touch()
            syncSettings { $0.dailyGoalMinutes = newValue }
        }
    }

    let dailyGoalOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

    // MARK: - Voice & playback

    var autoplayTeacherAudio: Bool {
        get { user.settings.autoplayTeacherAudio }
        set {
            guard user.settings.autoplayTeacherAudio != newValue else { return }
            user.settings.autoplayTeacherAudio = newValue
            touch()
            syncSettings { $0.autoplayTeacherAudio = newValue }
        }
    }

    // MARK: - Account

    /// Источник правды — `SubscriptionService` (Apphud + сервер).
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    var subscriptionLabel: String {
        isPremium
            ? L10n.tr("settings.subscription.premium", "Premium")
            : L10n.tr("settings.subscription.free", "Free")
    }

    var dailyGoalDisplay: String {
        L10n.tr("settings.daily_goal_value", "%lld min", dailyGoalMinutes)
    }

    func dailyGoalDisplay(for minutes: Int) -> String {
        L10n.tr("settings.daily_goal_value", "%lld min", minutes)
    }

    func signOut() {
        AuthService.shared.signOut()
        wipeLocalUser()
    }

    /// Удаление аккаунта: сначала DELETE /v1/me (сервер вычищает),
    /// потом локальный wipe.
    func deleteAccount() async {
        await AuthService.shared.deleteAccount()
        wipeLocalUser()
    }

    // MARK: - Private

    private func wipeLocalUser() {
        context.delete(user)
        try? context.save()
    }

    private func touch() {
        user.updatedAt = .now
        repository.save()
    }

    /// Отправить точечный PATCH `/v1/me/settings`. Локально UI уже поменялся
    /// оптимистично; при ошибке — показываем alert (юзер сможет попробовать
    /// ещё раз с помощью следующего изменения).
    private func syncSettings(mutate: (inout MeAPI.PatchSettings) -> Void) {
        var patch = MeAPI.PatchSettings()
        mutate(&patch)
        Task { [weak self] in
            do {
                _ = try await MeAPI.updateSettings(patch)
            } catch {
                self?.syncError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    /// PATCH `/v1/me/learning-profiles/{serverId}`. Если у профиля ещё нет
    /// serverId (не синкнулся) — пропускаем PATCH и триггерим полный `syncMe`,
    /// чтобы бэк подтвердил и вернул id.
    private func syncLearningProfile(
        _ profile: LearningProfileEntity,
        mutate: (inout MeAPI.UpdateLanguage) -> Void
    ) {
        var patch = MeAPI.UpdateLanguage()
        mutate(&patch)
        Task { [weak self] in
            guard let sid = profile.serverId else {
                _ = await AuthService.shared.syncMe()
                return
            }
            do {
                _ = try await MeAPI.updateLanguage(id: sid, patch)
            } catch {
                self?.syncError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }
}
