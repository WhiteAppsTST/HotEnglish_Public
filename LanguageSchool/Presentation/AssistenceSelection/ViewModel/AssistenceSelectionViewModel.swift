import Foundation

@MainActor
@Observable
final class AssistenceSelectionViewModel {

    private let user: UserEntity
    private let repository: UserRepository
    private let playback = PlaybackService()

    /// Локальный выбор в UI. В user.settings пишется только по кнопке Study with X.
    var selectedTeacher: TeacherProfile

    init(user: UserEntity, repository: UserRepository) {
        self.user = user
        self.repository = repository
        self.selectedTeacher = user.settings.selectedTeacher
    }

    // MARK: - Derived

    var teachers: [TeacherProfile] { TeacherProfile.allCases }

    /// Источник правды — `SubscriptionService` (Apphud + сервер).
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    /// Активный язык обучения — для выбора нужного choose-войса (SP/US).
    var currentLanguage: LanguageCode { user.settings.currentLearningLanguage }

    var canStudy: Bool { selectedTeacher.isFreeTier || isPremium }

    /// Сердечки за уже завязанное отношение с этим учителем на активном языке.
    /// 0 если отношение ещё не создано.
    var heartsForSelected: Int {
        user.relationship(
            with: selectedTeacher,
            in: user.settings.currentLearningLanguage
        )?.heartsForUI ?? 0
    }

    // MARK: - Actions

    func selectTeacher(_ teacher: TeacherProfile) {
        selectedTeacher = teacher
    }

    func playSample() {
        let file = selectedTeacher.voiceSampleFileName as NSString
        let name = file.deletingPathExtension
        let ext = file.pathExtension
        playback.play(bundleResource: name, ext: ext.isEmpty ? "mp3" : ext)
    }

    /// Записать выбор в user.settings и сохранить. Оптимистично пишет
    /// локально, потом синкает `PATCH /me/settings`. `TeacherRelationship` для
    /// новой пары создаст сервер — `MeMapper` подхватит в следующем `syncMe`.
    func commit() {
        let chosen = selectedTeacher
        user.settings.selectedTeacher = chosen
        user.updatedAt = .now
        repository.save()
        Task {
            _ = try? await MeAPI.updateSettings(.init(
                selectedTeacher: chosen.rawValue
            ))
            await AuthService.shared.syncMe()
        }
    }
}
