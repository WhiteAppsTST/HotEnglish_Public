import Foundation

@MainActor
@Observable
final class ProfileViewModel {

    let user: UserEntity
    private let repository: UserRepository

    /// Текущий изучаемый язык, отраженный из `user.settings`. Держим
    /// как @Observable-хранимое поле VM — если оставить это computed
    /// над `user.settings.currentLearningLanguage`, SwiftUI не будет
    /// перерисовывать Profile при mutation: `@Observable`-VM не тречит
    /// внутренности SwiftData `@Model`-объекта, поэтому segmented
    /// селектор остаётся на старом языке даже после `selectLanguage`.
    private(set) var currentLanguage: LanguageCode

    init(user: UserEntity, repository: UserRepository) {
        self.user = user
        self.repository = repository
        self.currentLanguage = user.settings.currentLearningLanguage
    }

    /// Пересобрать актуальный язык из user (после `syncMe` или
    /// возврата из ManageLanguageView). Вызывать на .onAppear.
    func refreshFromUser() {
        currentLanguage = user.settings.currentLearningLanguage
    }

    // MARK: - Actions

    /// Переключает изучаемый язык. Оптимистично апдейтит локально, потом
    /// PATCH `/me/settings` — все производные (уровень, прогресс, hearts на
    /// этом языке) сервер вернёт в следующем `syncMe`.
    func selectLanguage(_ language: LanguageCode) {
        guard user.settings.currentLearningLanguage != language else { return }
        user.settings.currentLearningLanguage = language
        user.updatedAt = .now
        currentLanguage = language   // тригерит перерисовку сегмента
        repository.save()
        // Гейт против параллельного syncMe (напр. HomeVM.onAppear), который
        // может успеть раньше нашего PATCH и вернуть старый язык. Держим
        // всю операцию под ним, снимаем только после commit-syncMe.
        MeMapper.suppressCurrentLearningLanguageMirror = true
        Task {
            defer { MeMapper.suppressCurrentLearningLanguageMirror = false }
            _ = try? await MeAPI.updateSettings(.init(
                currentLearningLanguage: language.rawValue
            ))
            await AuthService.shared.syncMe()
            // syncMe мог обновить user.settings со стороны сервера —
            // подтянуть локально, чтобы UI отражал результат.
            self.refreshFromUser()
        }
    }

    // MARK: - Identity

    var name: String { user.name.isEmpty ? "User" : user.name }
    var initial: String { String(name.prefix(1)).uppercased() }
    /// Источник правды — `SubscriptionService` (Apphud + сервер).
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    // MARK: - Learning plan

    struct LanguageRow: Identifiable, Hashable {
        let language: LanguageCode
        let level: LangGrade
        let progressPercent: Int
        var id: LanguageCode { language }
    }

    /// Порядок фиксирован (es → en) чтобы ячейки не прыгали при переключении.
    /// Селектор двигает только розовый бабл, сами клетки статичны.
    /// В сегменте показываем только языки с реальным `LearningProfile` —
    /// как и было. Появление Spanish после `Switch to Spanish` теперь
    /// обеспечивает `ManageLanguageViewModel.commit()`: он делает
    /// `POST /me/learning-profiles` перед PATCH settings, `syncMe` тянет
    /// свежий /me со Spanish-профилем, ProfileVM видит его естественно.
    var languages: [LanguageRow] {
        let fixedOrder: [LanguageCode] = [.es, .en]
        return fixedOrder.compactMap { lang in
            guard let profile = user.learningProfiles.first(where: { $0.languageCode == lang }) else { return nil }
            return LanguageRow(
                language: lang,
                level: profile.level,
                progressPercent: progressPercent(for: lang)
            )
        }
    }

    private func progressPercent(for lang: LanguageCode) -> Int {
        guard let profile = user.learningProfiles.first(where: { $0.languageCode == lang }) else { return 0 }
        // Реальный тотал = все шаги уровня из серверного контента (в кэше
        // после первого GET /content). Если кэш не подгружен — 0%
        // до первого возвращения `refreshUnitsFromServer` на Home.
        guard let bundle = ContentService.shared.cachedBundle(for: lang) else { return 0 }
        let totalSteps = ContentMapper.map(bundle)
            .filter { $0.grade == profile.level }
            .flatMap(\.steps)
            .count
        guard totalSteps > 0 else { return 0 }
        let done = profile.completedStepIds.count
        let ratio = Double(min(done, totalSteps)) / Double(totalSteps)
        return Int((ratio * 100).rounded())
    }

    // MARK: - Streak

    /// 7-дневное окно: 3 дня до сегодня, сегодня в центре, 3 дня после.
    struct StreakDay: Identifiable, Hashable {
        let date: Date
        let isToday: Bool
        let isCompleted: Bool
        let isFuture: Bool
        /// Порядковый номер в цепочке пройденных дней недели (1..)
        let orderInStreak: Int?
        var id: Date { date }
    }

    var streakWeek: [StreakDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let activeSet = user.streak.activeDaysThisWeek

        var result: [StreakDay] = []
        var streakCounter = 0

        for offset in -3...3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let isFuture = offset > 0
            let isToday = offset == 0
            // Приоритет — точный список активных дней недели из
            // `StreakOut.activeDaysThisWeek` (сервер). Fallback на эвристику
            // «≤ currentStreak дней назад» — если сет пустой (первый запуск).
            let isCompleted: Bool
            if isFuture {
                isCompleted = false
            } else if !activeSet.isEmpty {
                isCompleted = activeSet.contains(Weekday.from(date: day, calendar: calendar))
            } else {
                let daysAgo = -offset
                isCompleted = daysAgo < user.streak.currentStreak
            }
            var order: Int? = nil
            if isCompleted {
                streakCounter += 1
                order = streakCounter
            }
            result.append(StreakDay(
                date: day,
                isToday: isToday,
                isCompleted: isCompleted,
                isFuture: isFuture,
                orderInStreak: order
            ))
        }
        return result
    }

    var currentStreak: Int { user.streak.currentStreak }
    var bestStreak: Int { user.streak.bestStreak }

    // MARK: - Teacher

    var teacher: TeacherProfile { user.settings.selectedTeacher }
    var teacherHearts: Int {
        user.relationship(with: teacher, in: currentLanguage)?.heartsForUI ?? 0
    }

    /// «American · warm and patient» — берём одну готовую локализованную строку
    /// на учителя из каталога (парсинг description'а сломан в других языках).
    var teacherSubtitle: String {
        switch teacher {
        case .emma:      L10n.tr("teacher.subtitle.emma", "American · warm and patient")
        case .mia:       L10n.tr("teacher.subtitle.mia", "Colombian · playful and energetic")
        case .charlotte: L10n.tr("teacher.subtitle.charlotte", "British · elegant and distant")
        case .yuki:      L10n.tr("teacher.subtitle.yuki", "Japanese · quiet and gentle")
        case .aria:      L10n.tr("teacher.subtitle.aria", "American · bold and teasing")
        }
    }

    // MARK: - Finished lessons

    var unitsCompletedCount: Int {
        user.activeLearningProfile?.completedUnitIds.count ?? 0
    }

    var lessonsCount: Int {
        user.activeLearningProfile?.lessonsCount ?? 0
    }

    var averageScore: Int {
        user.activeLearningProfile?.averageScore ?? 0
    }

    var spokenTimeFormatted: String {
        let seconds = user.activeLearningProfile?.totalSecondsSpoken ?? 0
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
