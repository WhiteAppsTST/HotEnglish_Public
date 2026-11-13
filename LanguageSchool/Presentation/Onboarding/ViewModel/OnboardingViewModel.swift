import Foundation

@MainActor
@Observable
final class OnboardingViewModel {
    private let micService: MicPermissionManaging = MicPermissionManager()
    private let lessonsReminderService: LessonReminderScheduling = LessonReminderService()

    private let user: UserEntity
    private let repository: UserRepository
    private let onFinished: () -> Void

    var currentStep: OnboardingStep = .one
    var name: String
    var selectedLanguage: LanguageCode = .en
    var selectedGoal: LearningGoal?
    var reminderTime: Date = OnboardingViewModel.defaultReminderTime()
    var reminderEnabled: Bool = true
    var selectedGrade: LangGrade = .aOne
    var selectedTeacher: TeacherProfile = .emma

    var isTimePickerShown: Bool = false

    /// Идёт ли сейчас коммит на бэк (POST/PATCH сервера). Кнопка «Start with X»
    /// должна показывать spinner и быть disabled пока true.
    var isCommitting: Bool = false
    /// Локализованное сообщение об ошибке коммита. Триггерит alert в view.
    var commitError: String?

    init(
        user: UserEntity,
        repository: UserRepository,
        onFinished: @escaping () -> Void
    ) {
        self.user = user
        self.repository = repository
        self.onFinished = onFinished
        self.name = user.name
    }

    // MARK: - Derived

    var bgImage: String {
        selectedTeacher.backgroundImageName
    }

    var reminderHourString: String {
        String(format: "%02d", Calendar.current.component(.hour, from: reminderTime))
    }

    var reminderMinuteString: String {
        String(format: "%02d", Calendar.current.component(.minute, from: reminderTime))
    }

    var canAdvance: Bool {
        switch currentStep {
        case .one:   !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .three: selectedGoal != nil
        default:     true
        }
    }

    // MARK: - Navigation

    func nexStep() {
        switch currentStep {
        case .one:
            persistName()
            currentStep = .two
        case .two:   currentStep = .three
        case .three: currentStep = .four
        case .four:  currentStep = .five
        case .five:
            scheduleReminder()
            currentStep = .six
        case .six:   currentStep = .seven
        case .seven: Task { await commit() }
        }
    }

    /// Пишем имя локально и на бэк сразу как юзер прошёл первый шаг —
    /// чтобы при рестарте (не дошёл до финала) введённое имя не терялось.
    private func persistName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != user.name else { return }
        user.name = trimmed
        user.updatedAt = .now
        repository.save()
        Task {
            _ = try? await MeAPI.updateProfile(.init(name: trimmed))
        }
    }

    // MARK: - Step actions
    func selectGoal(_ goal: LearningGoal) {
        selectedGoal = goal
    }

    func requestMicPermissionAndProceed() {
        // Онбординг никогда не тащит юзера в Настройки. Спрашиваем только если
        // статус ещё .undetermined. Если уже granted/denied — просто идём дальше.
        guard micService.current == .undetermined else {
            nexStep()
            return
        }
        micService.ensureAccess { [weak self] _ in
            self?.nexStep()
        }
    }

    func scheduleReminder() {
        guard reminderEnabled else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        // На онбординге не тащим юзера в Настройки — если он отклонил
        // уведомления, просто пропускаем планирование. Позже во вкладке
        // Notifications он сможет включить их явно, там redirect в Settings
        // будет уместен.
        lessonsReminderService.status { [weak self] status in
            guard status == .granted else { return }
            self?.lessonsReminderService.scheduleDaily(at: comps) { _ in }
        }
    }

    /// Запросить пермишн на уведомления. Вью зовёт это, когда экран time
    /// picker'а (шаг 5) реально появился на экране, чтобы системный алерт
    /// вспыл прямо поверх него, а не на других шагах.
    /// Онбординг НЕ редиректит в Настройки — если статус уже granted/denied,
    /// ничего не делаем.
    func requestNotificationAccessIfNeeded() {
        lessonsReminderService.status { [weak self] status in
            guard status == .undetermined else { return }
            self?.lessonsReminderService.requestAccess { _ in }
        }
    }

    func showTimePicker() {
        isTimePickerShown.toggle()
    }

    func selectTeacher(_ teacher: TeacherProfile) {
        selectedTeacher = teacher
    }

    // MARK: - Commit

    /// Финализирует онбординг: отправляет выбор на бэк, потом синкает `MeDTO`
    /// (MeMapper сам создаст `LearningProfileEntity` и `TeacherRelationshipEntity`
    /// из ответа), локально выставляет `isOnboardingDone`, зовёт onFinished.
    ///
    /// Порядок такой чтобы не задваивать сущности: локально мы их не создаём,
    /// сервер — источник истины. Если бэк отказал — оставляем юзера на
    /// последнем экране онбординга и показываем ошибку.
    func commit() async {
        guard !isCommitting else { return }
        isCommitting = true
        defer { isCommitting = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let goal = selectedGoal ?? .somethingElse

        do {
            if !trimmedName.isEmpty, trimmedName != user.name {
                try await tolerant { _ = try await MeAPI.updateProfile(.init(name: trimmedName)) }
            }

            do {
                // POST /learning-profiles идемпотентен по languageCode —
                // сервер возвращает СУЩЕСТВУЮЩИЙ профиль (со старыми level/
                // goal), новые значения из тела игнорирует. Ловим DTO, чтобы
                // при mismatch дожать PATCH.
                let dto = try await MeAPI.startLanguage(.init(
                    languageCode: selectedLanguage.rawValue,
                    level: selectedGrade.rawValue,
                    goal: goal.rawValue
                ))
                if dto.level != selectedGrade.rawValue || dto.goal != goal.rawValue {
                    try await tolerant {
                        _ = try await MeAPI.updateLanguage(id: dto.id, .init(
                            level: selectedGrade.rawValue,
                            goal: goal.rawValue
                        ))
                    }
                }
            } catch APIError.conflict {
                // Совсем экзотика — язык залочен на другой уровень
                // серверной логикой. Не критично для онбординга.
            } catch APIError.decoding {
                // Сервер принял (2xx), но DTO не парсится — идём дальше.
            }

            let hour = Calendar.current.component(.hour, from: reminderTime)
            let minute = Calendar.current.component(.minute, from: reminderTime)
            try await tolerant { _ = try await MeAPI.updateSettings(.init(
                currentLearningLanguage: selectedLanguage.rawValue,
                selectedTeacher: selectedTeacher.rawValue,
                reminder: reminderEnabled ? .init(hour: hour, minute: minute) : nil,
                disableReminder: !reminderEnabled
            )) }

            // PATCH /me с isOnboardingDone=true — фиксируем на сервере,
            // чтобы relogin/переустановка не откатывали онбординг.
            try await tolerant { _ = try await MeAPI.updateProfile(.init(isOnboardingDone: true)) }

            // Сервер обновил профиль — тянем свежий документ, MeMapper зеркалит
            // в SwiftData. Локальный set ниже — на случай если mapper по каким-то
            // причинам не перезаписал (страховка + мгновенный UI).
            await AuthService.shared.syncMe()

            if !trimmedName.isEmpty { user.name = trimmedName }
            user.isOnboardingDone = true
            user.updatedAt = .now
            repository.save()

            onFinished()
        } catch let api as APIError {
            commitError = api.localizedDescription
        } catch {
            commitError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Оборачивает API-вызов так, чтобы decoding-ошибка на 2xx-ответе НЕ
    /// валила весь commit. Сервер принял (запрос пришёл на бэк), просто
    /// вернул body не в том формате что ждёт клиент — не критично для
    /// прохождения онбординга, `syncMe()` подтянет актуальное состояние.
    private func tolerant(_ call: () async throws -> Void) async throws {
        do {
            try await call()
        } catch APIError.decoding {
            // proceed
        }
    }

    private static func defaultReminderTime() -> Date {
        var comps = DateComponents()
        comps.hour = 12
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
