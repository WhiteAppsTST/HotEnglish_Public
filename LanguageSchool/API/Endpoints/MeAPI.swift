import Foundation

// MARK: - Response DTOs (строго по OpenAPI-схеме сервера)

struct MeDTO: Decodable {
    let id: String
    let externalAuthId: String?
    let provider: String?
    let email: String?
    let name: String?          // сервер: nullable
    let avatarUrl: String?
    let isPremium: Bool
    let isOnboardingDone: Bool?
    let nativeLanguageCode: String?
    let timezone: String?
    let settings: MeSettingsDTO
    let streak: StreakDTO?
    let learningProfiles: [LearningProfileDTO]
    let teacherRelationships: [TeacherRelationshipDTO]
    let createdAt: Date?
    let updatedAt: Date?
}

struct MeSettingsDTO: Decodable {
    let currentLearningLanguage: String
    let selectedTeacher: String
    let dailyGoalMinutes: Int
    let reminder: ReminderOutDTO?
    let autoplayTeacherAudio: Bool
}

struct ReminderOutDTO: Codable {
    let hour: Int
    let minute: Int
}

struct StreakDTO: Decodable {
    let currentStreak: Int
    let bestStreak: Int
    let lastActiveDay: Date?
    let activeDaysThisWeek: [Int]?
}

struct LearningProfileDTO: Decodable {
    let id: String
    let languageCode: String
    let level: String
    let goal: String
    let currentUnitId: String?
    let currentStepId: String?
    let completedUnitIds: [String]
    let completedStepIds: [String]
    let lessonsCount: Int
    let averageScore: Int
    let totalSecondsSpoken: Int
    let startedAt: Date?
    let lastActivityAt: Date?
    let updatedAt: Date?
}

struct TeacherRelationshipDTO: Decodable {
    let id: String?
    let teacher: String
    let languageCode: String
    let affinity: Int?
    let hearts: Int
    let lessonsTogether: Int
    let lastInteractionAt: Date?
    let updatedAt: Date?
}

// MARK: - Endpoints

@MainActor
enum MeAPI {

    static func me() async throws -> MeDTO {
        try await APIClient.shared.send(.GET, "/v1/me")
    }

    /// `PATCH /v1/me` — только поля из спеки, `Extra inputs are not permitted`
    /// на сервере строгий. Nil-поля пропускаются через `encodeIfPresent`.
    struct PatchMe: Encodable {
        var name: String?
        var avatarUrl: String?
        var nativeLanguageCode: String?
        var timezone: String?
        var isOnboardingDone: Bool?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(name, forKey: .name)
            try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
            try c.encodeIfPresent(nativeLanguageCode, forKey: .nativeLanguageCode)
            try c.encodeIfPresent(timezone, forKey: .timezone)
            try c.encodeIfPresent(isOnboardingDone, forKey: .isOnboardingDone)
        }

        enum CodingKeys: String, CodingKey {
            case name, avatarUrl, nativeLanguageCode, timezone, isOnboardingDone
        }
    }
    static func updateProfile(_ patch: PatchMe) async throws -> MeDTO {
        try await APIClient.shared.send(.PATCH, "/v1/me", body: patch)
    }

    /// `PATCH /v1/me/settings` — `reminder` вложенный объект `{hour, minute}`,
    /// либо не отсылается, либо null для отключения. Для явного отключения
    /// напоминаний передаём `disableReminder = true`.
    struct PatchSettings: Encodable {
        var currentLearningLanguage: String?
        var selectedTeacher: String?
        var dailyGoalMinutes: Int?
        var autoplayTeacherAudio: Bool?
        var reminder: ReminderOutDTO?
        var disableReminder: Bool = false

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(currentLearningLanguage, forKey: .currentLearningLanguage)
            try c.encodeIfPresent(selectedTeacher, forKey: .selectedTeacher)
            try c.encodeIfPresent(dailyGoalMinutes, forKey: .dailyGoalMinutes)
            try c.encodeIfPresent(autoplayTeacherAudio, forKey: .autoplayTeacherAudio)
            if disableReminder {
                try c.encodeNil(forKey: .reminder)
            } else if let r = reminder {
                try c.encode(r, forKey: .reminder)
            }
        }

        enum CodingKeys: String, CodingKey {
            case currentLearningLanguage, selectedTeacher, dailyGoalMinutes,
                 autoplayTeacherAudio, reminder
        }
    }
    static func updateSettings(_ patch: PatchSettings) async throws -> MeDTO {
        try await APIClient.shared.send(.PATCH, "/v1/me/settings", body: patch)
    }

    /// DELETE /v1/me — требование App Store.
    static func deleteAccount() async throws {
        _ = try await APIClient.shared.send(.DELETE, "/v1/me")
    }

    struct StartLanguage: Encodable {
        let languageCode: String
        let level: String
        let goal: String
    }
    static func startLanguage(_ body: StartLanguage) async throws -> LearningProfileDTO {
        try await APIClient.shared.send(.POST, "/v1/me/learning-profiles", body: body)
    }

    struct UpdateLanguage: Encodable {
        var level: String?
        var goal: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(level, forKey: .level)
            try c.encodeIfPresent(goal, forKey: .goal)
        }

        enum CodingKeys: String, CodingKey { case level, goal }
    }
    static func updateLanguage(id: String, _ body: UpdateLanguage) async throws -> LearningProfileDTO {
        try await APIClient.shared.send(.PATCH, "/v1/me/learning-profiles/\(id)", body: body)
    }
}
