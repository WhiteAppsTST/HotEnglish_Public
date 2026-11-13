import Foundation
import SwiftData

@Model
final class UserEntity {
    @Attribute(.unique) var id: UUID

    /// Provider-issued id (Apple credential.user / Google userID). Used to
    /// find the local User at sign-in before a backend exists.
    var externalAuthId: String
    var provider: AuthProvider

    var email: String?
    var name: String
    var avatarURL: URL?

    var isPremium: Bool
    var isOnboardingDone: Bool

    var createdAt: Date
    var updatedAt: Date

    var settings: UserSettings
    var streak: StreakTracker

    @Relationship(deleteRule: .cascade, inverse: \LearningProfileEntity.user)
    var learningProfiles: [LearningProfileEntity]

    @Relationship(deleteRule: .cascade, inverse: \TeacherRelationshipEntity.user)
    var teacherRelationships: [TeacherRelationshipEntity]

    init(
        id: UUID = UUID(),
        externalAuthId: String,
        provider: AuthProvider,
        email: String? = nil,
        name: String,
        avatarURL: URL? = nil,
        isPremium: Bool = false,
        isOnboardingDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        settings: UserSettings = .default,
        streak: StreakTracker = .empty,
        learningProfiles: [LearningProfileEntity] = [],
        teacherRelationships: [TeacherRelationshipEntity] = []
    ) {
        self.id = id
        self.externalAuthId = externalAuthId
        self.provider = provider
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
        self.isPremium = isPremium
        self.isOnboardingDone = isOnboardingDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.settings = settings
        self.streak = streak
        self.learningProfiles = learningProfiles
        self.teacherRelationships = teacherRelationships
    }
}

// MARK: - Convenience access

extension UserEntity {

    func learningProfile(for language: LanguageCode) -> LearningProfileEntity? {
        learningProfiles.first { $0.languageCode == language }
    }

    var activeLearningProfile: LearningProfileEntity? {
        learningProfile(for: settings.currentLearningLanguage)
    }

    func relationship(with teacher: TeacherProfile, in language: LanguageCode) -> TeacherRelationshipEntity? {
        teacherRelationships.first { $0.teacher == teacher && $0.languageCode == language }
    }

    var activeRelationship: TeacherRelationshipEntity? {
        relationship(with: settings.selectedTeacher, in: settings.currentLearningLanguage)
    }
}
