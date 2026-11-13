import Foundation

@MainActor
@Observable
final class HomeViewModel {
    let user: UserEntity
    let quota: LessonQuotaService
    var units: [Unit] = []
    var expandedUnitId: String?

    /// Показываем ли скелетон юнитов вместо реального списка.
    /// TODO: при появлении backend'а держать `true` пока идёт `GET /content/{languageCode}`,
    /// сбрасывать в `false` после успешного fetch или на ошибку (показать retry).
    var isLoading: Bool = false

    /// Push-бабл над видео учительницы. По ТЗ (sec_327) верхняя часть экрана
    /// показывает «подобные пуши, флирт». Строка тянется с бэка через
    /// `GET /v1/me/teachers/{teacher}/daily-quote` — сервер кеширует её на день.
    /// До ответа сервера — локальный fallback.
    var teacherQuote: String = L10n.tr("home.teacher_quote", "I keep thinking about what you said yesterday.")

    // TODO: заменить на chat unread endpoint (сейчас показываем оставшиеся
    // фри-тексты — это и есть тот же счётчик что в TalkView).
    var talkUnreadCount: Int { talkFreeTextsRemaining }

    /// Presented «Message from teacher» sheet (Figma 373:3287).
    /// Открывается когда юзер входит в приложение по пушу об отсутствии.
    /// TODO: реальный триггер — из push-handler'а (didReceive
    /// notificationResponse) вызывать `homeVM.presentAwayMessage(.init(...))`.
    var awayMessage: AwayMessageData?

    func presentAwayMessage(_ data: AwayMessageData) {
        awayMessage = data
    }

    func dismissAwayMessage() {
        awayMessage = nil
    }

    init(user: UserEntity, quota: LessonQuotaService? = nil) {
        self.user = user
        // Живой enforcement идёт через singleton — иначе Home и LessonView
        // видели бы разные счётчики. Тесты могут инжектить свой инстанс.
        self.quota = quota ?? .shared
        loadUnitsFromCache()
        expandedUnitId = firstActiveUnit()?.id
    }

    func onAppear() {
        quota.refreshIfExpired()
        Task { await refreshUnitsFromServer() }
        Task { await refreshDailyQuote() }
        // Возврат с урока — тянем свежий /me чтобы обновить completedStepIds,
        // hearts, streak. Реактивно перерисует UnitCard "Done".
        Task { await AuthService.shared.syncMe() }
    }

    /// Тянет `daily-quote` для текущей учительницы. Сервер кеширует ответ на
    /// сутки локального времени юзера, так что можно дёргать безбоязно.
    func refreshDailyQuote() async {
        do {
            let dto = try await AiAPI.dailyQuote(teacher: teacher.rawValue)
            if !dto.text.isEmpty { teacherQuote = dto.text }
        } catch {
            // Молчим — оставляем локальный fallback.
        }
    }

    // MARK: - Derived (user)

    var teacher: TeacherProfile { user.settings.selectedTeacher }
    var language: LanguageCode { user.settings.currentLearningLanguage }
    var currentLevel: LangGrade { user.activeLearningProfile?.level ?? .aOne }
    var currentLevelDisplay: String { currentLevel.grade }

    var streakDays: Int { user.streak.currentStreak }
    var bestStreak: Int { user.streak.bestStreak }

    var progressInCurrentGrade: Double {
        guard let profile = user.activeLearningProfile else { return 0 }
        let steps = units.filter { $0.grade == profile.level }.flatMap(\.steps)
        guard !steps.isEmpty else { return 0 }
        let done = steps.filter { profile.completedStepIds.contains($0.id) }.count
        return Double(done) / Double(steps.count)
    }

    var progressPercent: Int { Int((progressInCurrentGrade * 100).rounded()) }

    /// Сырой процент отношений (0…100) с бэка. Источник — `TeacherRelationshipOut.affinity`.
    var affinityPercent: Int {
        max(0, min(100, user.activeRelationship?.affinity ?? 0))
    }

    /// Нормализованное значение для отрисовки полосы.
    var affinityFraction: Double { Double(affinityPercent) / 100.0 }

    /// Стадия отношений по ТЗ (sec_327): «Отношения: 67%, симпатия».
    /// Дефолтит на neutral если нет активных relationship'ов.
    var affinityStage: TeacherStage {
        user.activeRelationship?.stage ?? .neutral
    }
    var affinityStageLabel: String { affinityStage.localizedTitle }

    var talkBadgeText: String { talkUnreadCount > 99 ? "99+" : "\(talkUnreadCount)" }

    /// Для премиума в бейдже рисуем иконку бесконечности вместо числа —
    /// лимитов у него нет. Для free — число оставшихся текстов.
    var talkBadgeIsUnlimited: Bool { isPremium }

    // MARK: - Daily lesson quota

    /// Единственный источник правды по премиуму на клиенте —
    /// `SubscriptionService` (Apphud + серверный webhook). Поле
    /// `user.isPremium` (SwiftData mirror с /me) НЕ используется как гейт:
    /// оно отстаёт от Apphud'а сразу после покупки.
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    var isQuotaExhausted: Bool {
        !isPremium && quota.isExhausted
    }

    /// Свободные тексты в Talk (24h окно). Для free-юзера — реальный счётчик
    /// из TalkViewModel; premium — всегда полный.
    var talkFreeTextsRemaining: Int {
        isPremium ? TalkViewModel.freeTextsPerDay : TalkViewModel.freeTextsRemaining()
    }

    /// Свободный чат исчерпан — Talk-кнопка на Home меняет цвет на pink CTA.
    var isTalkQuotaExhausted: Bool {
        !isPremium && talkFreeTextsRemaining == 0
    }

    func quotaTimeRemaining(at now: Date = .now) -> String? {
        quota.timeRemainingString(at: now)
    }

    // MARK: - Unit queries

    func isUnitCompleted(_ unit: Unit) -> Bool {
        guard let profile = user.activeLearningProfile, !unit.steps.isEmpty else { return false }
        return unit.steps.allSatisfy { profile.completedStepIds.contains($0.id) }
    }

    func completedStepCount(in unit: Unit) -> Int {
        guard let profile = user.activeLearningProfile else { return 0 }
        return unit.steps.filter { profile.completedStepIds.contains($0.id) }.count
    }

    func isUnitLocked(_ unit: Unit) -> Bool {
        if unit.isPremium && !isPremium { return true }
        // ПЕРВЫЙ юнит уровня, выбранного юзером, всегда открыт — даже если
        // его `unlockRule` ссылается на юнит нижнего уровня (напр. B1 unit
        // ссылается на последний A2). Юзер выбрал уровень — с него и
        // стартует, а не проходит 120 юнитов A1/A2 подряд.
        if unit.grade == currentLevel,
           unitsForCurrentLevel.first?.id == unit.id {
            return false
        }
        switch unit.unlockRule {
        case .none: return false
        case .some(.afterUnit(let prevId)):
            guard let prev = units.first(where: { $0.id == prevId }) else { return true }
            return !isUnitCompleted(prev)
        }
    }

    // MARK: - Step queries

    func isStepCompleted(_ step: Step) -> Bool {
        user.activeLearningProfile?.completedStepIds.contains(step.id) ?? false
    }

    func isStepLocked(_ step: Step) -> Bool {
        switch step.unlockRule {
        case .none: return false
        case .some(.afterStep(let prevId)):
            return !(user.activeLearningProfile?.completedStepIds.contains(prevId) ?? false)
        }
    }

    func isCurrentStep(_ step: Step, in unit: Unit) -> Bool {
        firstActiveStep(in: unit)?.id == step.id
    }

    func firstActiveStep(in unit: Unit) -> Step? {
        unit.steps.first { !isStepCompleted($0) && !isStepLocked($0) }
    }

    /// «Активный» юнит для главного экрана — первый в списке, который ещё
    /// не пройден и не залочен. Если такого нет — возвращаем последний в
    /// списке (чтобы главный экран не был пустым).
    var currentUnit: Unit? {
        unitsForCurrentLevel.first { !isUnitCompleted($0) && !isUnitLocked($0) }
            ?? unitsForCurrentLevel.last
    }

    /// Юниты для текущего уровня. Home рисует только их — глобальный список
    /// контента (все A1/A2/B1 разом) даёт «Unit 121, 122…» — юзеру,
    /// выбравшему B1, не нужно 120 юнитов A1 сверху.
    var unitsForCurrentLevel: [Unit] {
        units.filter { $0.grade == currentLevel }
    }

    // MARK: - Expand / collapse

    func isExpanded(_ unit: Unit) -> Bool { expandedUnitId == unit.id }

    func toggleExpand(_ unit: Unit) {
        expandedUnitId = expandedUnitId == unit.id ? nil : unit.id
    }

    // MARK: - Private

    private func firstActiveUnit() -> Unit? {
        unitsForCurrentLevel.first { !isUnitCompleted($0) && !isUnitLocked($0) }
    }

    // MARK: - Content loading

    /// Мгновенно рисуем кэш при первом рендере. Пусто → показываем скелетон
    /// (via `isLoading`) пока `refreshUnitsFromServer()` не отдаст ответ.
    private func loadUnitsFromCache() {
        if let cached = ContentService.shared.cachedBundle(for: language) {
            units = ContentMapper.map(cached)
            isLoading = false
        } else {
            units = []
            isLoading = true
        }
    }

    /// Идёт в бэк c `If-None-Match`; 304 → ничего не делаем, 200 → пересобираем
    /// units и снимаем скелетон. Ошибки сети не эскалируем — юзер учится по
    /// кэшу, ретрайним на следующем onAppear.
    func refreshUnitsFromServer() async {
        let (dto, _) = await ContentService.shared.fetchBundle(
            for: language,
            level: currentLevel
        )
        if let dto {
            units = ContentMapper.map(dto)
            expandedUnitId = firstActiveUnit()?.id
        }
        isLoading = false
    }

    // MARK: - Mocks (drop when backend is wired)
    /// TODO: удалить когда реальный контент придёт с бэка.
    /// Пока оставили как fallback для тестов без сети.
    private static func mockUnits() -> [Unit] {
        [
            Unit(
                id: "unit_1", order: 1,
                title: "Introducing Yourself", iconName: "hand.wave.fill",
                isPremium: false, grade: .aOne, unlockRule: nil,
                steps: mockSteps(unit: 1, speakingSubtitle: "Introduce yourself. Out loud.")
            ),
            Unit(
                id: "unit_2", order: 2,
                title: "Ordering Coffee", iconName: "cup.and.saucer.fill",
                isPremium: false, grade: .aOne, unlockRule: .afterUnit("unit_1"),
                steps: mockSteps(unit: 2, speakingSubtitle: "\"Order me a coffee. Out loud.\"")
            ),
            Unit(
                id: "unit_3", order: 3,
                title: "Airport Small Talk", iconName: "✈️",
                isPremium: false, grade: .aTwo, unlockRule: .afterUnit("unit_2"),
                steps: mockSteps(unit: 3, speakingSubtitle: "Ask for directions. Out loud.")
            ),
            Unit(
                id: "unit_4", order: 4,
                title: "Getting Around Town", iconName: "🧭",
                isPremium: false, grade: .aTwo, unlockRule: .afterUnit("unit_3"),
                steps: mockSteps(unit: 4, speakingSubtitle: "Order a taxi. Out loud.")
            ),
            Unit(
                id: "unit_5", order: 5,
                title: "At the Restaurant", iconName: "🍽️",
                isPremium: true, grade: .aTwo, unlockRule: .afterUnit("unit_4"),
                steps: mockSteps(unit: 5, speakingSubtitle: "Order for two. Out loud.")
            ),
            Unit(
                id: "unit_6", order: 6,
                title: "Making Plans", iconName: "📅",
                isPremium: true, grade: .bOne, unlockRule: .afterUnit("unit_5"),
                steps: mockSteps(unit: 6, speakingSubtitle: "Suggest a plan. Out loud.")
            ),
            Unit(
                id: "unit_7", order: 7,
                title: "The Date Night", iconName: "🍷",
                isPremium: true, grade: .bOne, unlockRule: .afterUnit("unit_6"),
                steps: mockSteps(unit: 7, speakingSubtitle: "Compliment her. Out loud.")
            ),
            Unit(
                id: "unit_8", order: 8,
                title: "Morning After", iconName: "🌙",
                isPremium: true, grade: .bOne, unlockRule: .afterUnit("unit_7"),
                steps: mockSteps(unit: 8, speakingSubtitle: "Breakfast talk. Out loud.")
            )
        ]
    }

    private static func mockSteps(unit u: Int, speakingSubtitle: String) -> [Step] {
        [
            Step(id: "step_\(u)_1", order: 1, kind: .topicWords,
                 title: "Topic words", subtitle: "Picture cards · 8 words",
                 unlockRule: nil),
            Step(id: "step_\(u)_2", order: 2, kind: .grammar,
                 title: "Grammar", subtitle: "Put the words in order",
                 unlockRule: .afterStep("step_\(u)_1")),
            Step(id: "step_\(u)_3", order: 3, kind: .speaking,
                 title: "Speaking", subtitle: speakingSubtitle,
                 unlockRule: .afterStep("step_\(u)_2")),
            Step(id: "step_\(u)_4", order: 4, kind: .date,
                 title: "The date", subtitle: "Free voice · after step 3",
                 unlockRule: .afterStep("step_\(u)_3"))
        ]
    }
}
