import Foundation

nonisolated
struct UserSettings: Codable, Hashable, Sendable {
    var currentLearningLanguage: LanguageCode
    var selectedTeacher: TeacherProfile
    var dailyGoalMinutes: Int
    var autoplayTeacherAudio: Bool
    /// Язык, на который переводятся уроки/подсказки. Дефолт — English.
    var translationLanguage: LanguageCode

    static let `default` = UserSettings(
        currentLearningLanguage: .en,
        selectedTeacher: .emma,
        dailyGoalMinutes: 10,
        autoplayTeacherAudio: true,
        translationLanguage: .en
    )
}
