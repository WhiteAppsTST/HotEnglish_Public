import Foundation
import SwiftData

/// Правило: сервер — источник истины для профиля/прогресса. Мы лишь зеркалим
/// то, что пришло в `MeDTO`, в локальные SwiftData-сущности; никаких мутаций
/// «поверх» серверных значений на клиенте.
///
/// Идентификаторы:
///  - `UserEntity` находим по `externalAuthId == me.id` (сервер сам держит
///    стабильный id внутри своей системы; провайдер узнаём отдельно из
///    Keychain / Google SDK);
///  - `LearningProfileEntity` — по `languageCode`;
///  - `TeacherRelationshipEntity` — по (teacher, languageCode).
///
/// Всё что сервер прислал — перезаписывает. Всё что не прислал — не трогаем
/// (например `onboarding done`, `talkHistoryJSON` — чисто локальные).
@MainActor
enum MeMapper {

    /// Guard против гонки «клиент только что PATCH-нул язык → parallel
    /// syncMe (например HomeVM.onAppear) успел раньше и вернул старый
    /// currentLearningLanguage». Если true — `applySettings` НЕ трогает
    /// `user.settings.currentLearningLanguage`, все остальные поля
    /// зеркалятся как обычно. Ставится клиентом на время
    /// PATCH + commit-syncMe (см. `ManageLanguageViewModel.commit`).
    static var suppressCurrentLearningLanguageMirror: Bool = false

    // MARK: - Public

    /// Найти или создать `UserEntity` под DTO, обновить все зеркальные поля,
    /// вернуть сущность (уже вставленную в контекст). Провайдер приходит
    /// извне — берём из активного AuthUser.
    @discardableResult
    static func upsert(
        _ dto: MeDTO,
        provider: AuthProvider,
        in context: ModelContext
    ) -> UserEntity {
        let user = findOrCreate(dto: dto, provider: provider, in: context)
        applyIdentity(dto, to: user)
        applySettings(dto.settings, to: user)
        applyStreak(dto.streak, to: user)
        applyLearningProfiles(dto.learningProfiles, to: user)
        applyTeacherRelationships(dto.teacherRelationships, to: user)
        user.updatedAt = .now
        try? context.save()
        return user
    }

    // MARK: - User

    private static func findOrCreate(
        dto: MeDTO,
        provider: AuthProvider,
        in context: ModelContext
    ) -> UserEntity {
        let serverId = dto.id
        // 1. Пробуем найти по server id — стандартный кейс на повторных syncMe.
        let byServerId = FetchDescriptor<UserEntity>(
            predicate: #Predicate { $0.externalAuthId == serverId }
        )
        if let existing = (try? context.fetch(byServerId))?.first {
            existing.provider = provider
            return existing
        }
        // 2. Не нашли — но у нас мог остаться SKELETON-entity после
        //    `upsert(from: authUser)` с `externalAuthId = email` (dev
        //    sign-in) или apple userIdentifier. Дедуплицируем его — сравниваем
        //    email и externalAuthId вручную (SwiftData #Predicate на
        //    optional String работает шатко). Мигрируем externalAuthId на
        //    серверный. Без дедупа создавался ВТОРОЙ UserEntity, юзер
        //    заходил в онбординг заново после relogin.
        let all = (try? context.fetch(FetchDescriptor<UserEntity>())) ?? []
        let email = dto.email
        if let skeleton = all.first(where: { candidate in
            if let em = email, !em.isEmpty, candidate.email == em { return true }
            // dev sign-in: authUser.id = email → externalAuthId ==
            // "555@mail.com". Сервер: "dev:555@mail.com". Тоже совпадение.
            if let em = email, candidate.externalAuthId == em { return true }
            if let em = email, candidate.externalAuthId == "dev:\(em)" { return true }
            return false
        }) {
            skeleton.externalAuthId = serverId
            skeleton.provider = provider
            return skeleton
        }
        // 3. Свежая установка — создаём новый entity сразу с серверным id.
        let fresh = UserEntity(
            externalAuthId: dto.id,
            provider: provider,
            email: dto.email,
            name: (dto.name?.isEmpty == false) ? dto.name! : "User",
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:))
        )
        context.insert(fresh)
        return fresh
    }

    private static func applyIdentity(_ dto: MeDTO, to user: UserEntity) {
        user.email = dto.email
        if let name = dto.name, !name.isEmpty { user.name = name }
        user.avatarURL = dto.avatarUrl.flatMap(URL.init(string:))
        user.isPremium = dto.isPremium
        // Сервер — источник истины по онбордингу. Клиент выставит `true`
        // локально в commit, но и сервер должен это же значение прислать.
        // Без mirror-а после relogin пропадал бы флаг и юзер снова
        // попадал в онбординг.
        if let done = dto.isOnboardingDone { user.isOnboardingDone = done }
    }

    // MARK: - Settings

    private static func applySettings(_ dto: MeSettingsDTO, to user: UserEntity) {
        var s = user.settings
        if let teacher = TeacherProfile(rawValue: dto.selectedTeacher) {
            s.selectedTeacher = teacher
        }
        if !suppressCurrentLearningLanguageMirror,
           let lang = LanguageCode(rawValue: dto.currentLearningLanguage) {
            s.currentLearningLanguage = lang
        }
        s.dailyGoalMinutes = dto.dailyGoalMinutes
        s.autoplayTeacherAudio = dto.autoplayTeacherAudio
        user.settings = s
    }

    // MARK: - Streak

    private static func applyStreak(_ dto: StreakDTO?, to user: UserEntity) {
        guard let dto else { return }
        var s = user.streak
        s.currentStreak = dto.currentStreak
        s.bestStreak = dto.bestStreak
        s.lastActiveDay = dto.lastActiveDay
        if let days = dto.activeDaysThisWeek {
            s.activeDaysThisWeek = Set(days.compactMap(Weekday.init(rawValue:)))
        }
        user.streak = s
    }

    // MARK: - Learning profiles

    private static func applyLearningProfiles(
        _ dtos: [LearningProfileDTO],
        to user: UserEntity
    ) {
        for dto in dtos {
            guard let language = LanguageCode(rawValue: dto.languageCode) else { continue }
            let existing = user.learningProfiles.first { $0.languageCode == language }
            let target = existing ?? {
                let created = LearningProfileEntity(
                    languageCode: language,
                    level: LangGrade(rawValue: dto.level) ?? .aOne,
                    goal: LearningGoal(rawValue: dto.goal) ?? .somethingElse
                )
                created.user = user
                user.learningProfiles.append(created)
                return created
            }()

            target.serverId = dto.id
            if let level = LangGrade(rawValue: dto.level) { target.level = level }
            if let goal = LearningGoal(rawValue: dto.goal) { target.goal = goal }
            target.currentUnitId = dto.currentUnitId
            target.currentStepId = dto.currentStepId
            // completedUnitIds/completedStepIds — UNION со серверными, а не
            // replace. Иначе оптимистичный локальный mark из
            // `LessonViewModel.markStepCompletedLocally` стирается ближайшим
            // syncMe (например Home.onAppear), когда серверная сессия по
            // какой-то причине не долетела (429/timeout/etc), и юзер видит
            // «Continue» на только что пройденном шаге. Прогресс аддитивен —
            // сервер никогда не «убирает» уже пройденный шаг, так что union
            // безопасен и покрывает случай когда сервер отстаёт.
            target.completedUnitIds = Array(Set(target.completedUnitIds).union(dto.completedUnitIds))
            target.completedStepIds = Array(Set(target.completedStepIds).union(dto.completedStepIds))
            target.lessonsCount = max(target.lessonsCount, dto.lessonsCount)
            target.averageScore = dto.averageScore
            target.totalSecondsSpoken = max(target.totalSecondsSpoken, dto.totalSecondsSpoken)
            if let startedAt = dto.startedAt { target.startedAt = startedAt }
            target.updatedAt = .now
        }
    }

    // MARK: - Teacher relationships

    private static func applyTeacherRelationships(
        _ dtos: [TeacherRelationshipDTO],
        to user: UserEntity
    ) {
        for dto in dtos {
            guard let teacher = TeacherProfile(rawValue: dto.teacher),
                  let language = LanguageCode(rawValue: dto.languageCode)
            else { continue }

            let existing = user.teacherRelationships.first {
                $0.teacher == teacher && $0.languageCode == language
            }
            let target = existing ?? {
                let created = TeacherRelationshipEntity(
                    teacher: teacher,
                    languageCode: language
                )
                created.user = user
                user.teacherRelationships.append(created)
                return created
            }()

            // Сервер отдаёт 0…5 сердечек. Внутри клиента `affinity` 0…100
            // (шаг 20 на сердце) — держим совместимость с существующим UI
            // через `heartsForUI = affinity / 20`.
            let clamped = max(0, min(5, dto.hearts))
            target.affinity = clamped * 20
            target.lessonsTogether = dto.lessonsTogether
            target.updatedAt = .now
        }
    }
}
