import Foundation
import SwiftData

@Model
final class LearningProfileEntity {
    @Attribute(.unique) var id: UUID
    /// Идентификатор профиля на сервере (`LearningProfileDTO.id`).
    /// Нужен для точечных PATCH-ов на `/v1/me/learning-profiles/{id}`.
    /// Заполняется `MeMapper` при первой sync; nil означает что профиль
    /// создан локально и ещё не синкнулся.
    var serverId: String?
    var user: UserEntity?

    var languageCode: LanguageCode
    var level: LangGrade
    var goal: LearningGoal

    var currentUnitId: String?
    var currentStepId: String?
    var completedUnitIds: [String]
    var completedStepIds: [String]

    var totalSecondsSpoken: Int
    var lessonsCount: Int
    var averageScore: Int

    var startedAt: Date
    var lastActivityAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        languageCode: LanguageCode,
        level: LangGrade,
        goal: LearningGoal,
        currentUnitId: String? = nil,
        currentStepId: String? = nil,
        completedUnitIds: [String] = [],
        completedStepIds: [String] = [],
        totalSecondsSpoken: Int = 0,
        lessonsCount: Int = 0,
        averageScore: Int = 0,
        startedAt: Date = .now,
        lastActivityAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.languageCode = languageCode
        self.level = level
        self.goal = goal
        self.currentUnitId = currentUnitId
        self.currentStepId = currentStepId
        self.completedUnitIds = completedUnitIds
        self.completedStepIds = completedStepIds
        self.totalSecondsSpoken = totalSecondsSpoken
        self.lessonsCount = lessonsCount
        self.averageScore = averageScore
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.updatedAt = updatedAt
    }
}
