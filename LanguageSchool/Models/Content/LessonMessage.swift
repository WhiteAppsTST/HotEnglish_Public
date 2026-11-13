import Foundation

/// Одна реплика в уроке. `assistant` — учительница, `user` — юзер.
/// `hintUsed` — только для user-реплик, показывает был ли использован hint
/// (иконка ? в баббле).
nonisolated
struct LessonMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable { case assistant, user }

    let id: String
    let role: Role
    let text: String
    /// Для user-реплики: юзер применил hint при формулировке ответа.
    let hintUsed: Bool
    /// Сообщение в очереди на отправку (offline). Рендерится как тёмно-винный
    /// бабл с приглушённым текстом + подпись «Will send when you're back
    /// online» (Figma 373:4639).
    let isQueued: Bool

    init(id: String, role: Role, text: String, hintUsed: Bool, isQueued: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.hintUsed = hintUsed
        self.isQueued = isQueued
    }
}

/// Фаза урока. Табы в топе content-области.
nonisolated
enum LessonPhase: String, Sendable, CaseIterable, Identifiable {
    case lecture
    case practice
    var id: Self { self }
    var title: String {
        switch self {
        case .lecture:  "Lecture"
        case .practice: "Practice"
        }
    }
}

/// Мок-контент урока. TODO: заменить на fetch с бэка:
/// `GET /content/lesson/{stepId}?languageCode={code}`
/// возвращающий `[LessonMessage]` + мета (общее кол-во под-табов, начальная
/// фаза, доступные hints).
enum LessonContent {

    /// Пока отдаём один assistant-приветственный месседж независимо от step-а.
    /// Backend должен отдавать полный сценарий (Lecture + Practice реплики) под
    /// конкретный `step.kind` и язык обучения.
    static func mock(for step: Step, language: LanguageCode) -> [LessonMessage] {
        switch language {
        case .en:
            return [
                LessonMessage(
                    id: "\(step.id)_l_1",
                    role: .assistant,
                    text: "Hello Alex! How is your day going so far? Today, you will learn how to greet people. Are you ready to start?",
                    hintUsed: false
                )
            ]
        case .es:
            return [
                LessonMessage(
                    id: "\(step.id)_l_1",
                    role: .assistant,
                    text: "¡Hola Alex! ¿Cómo va tu día? Hoy vas a aprender a saludar a las personas. ¿Listo para empezar?",
                    hintUsed: false
                )
            ]
        }
    }
}
