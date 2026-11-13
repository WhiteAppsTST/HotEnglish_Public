import Foundation

/// Одна ключевая фраза с переводом и аудио (Figma 373:2487, «Key phrases»).
/// Показывается в Lecture-режиме под assistant-баблом.
/// TODO: заменить моки на fetch с бэка.
nonisolated
struct KeyPhrase: Identifiable, Hashable, Sendable {
    let id: String
    let native: String
    let translation: String
    /// Локальное имя файла в бандле (для моков). Оставлено для совместимости.
    let audioName: String?
    /// Абсолютный `audioUrl` с бэка (`Word.audioUrl`) — приоритет над локальным.
    let audioUrl: URL?

    init(id: String, native: String, translation: String, audioName: String? = nil, audioUrl: URL? = nil) {
        self.id = id
        self.native = native
        self.translation = translation
        self.audioName = audioName
        self.audioUrl = audioUrl
    }
}

/// Pattern-карточка (Figma 373:2487, «Pattern»). Содержит **несколько
/// примеров** (2+) разделённых линией. Каждый пример — фраза с розовым
/// highlight-префиксом + перевод + play-кнопка.
nonisolated
struct PatternExample: Identifiable, Hashable, Sendable {
    let id: String
    let formula: String        // "me gustaría + infinitive"
    let examples: [Example]    // Figma 373:2487 показывает 2 примера

    struct Example: Hashable, Sendable, Identifiable {
        let id: String
        let text: String            // "Me gustaría beber algo"
        let highlightPrefix: String // "Me gustaría"
        let translation: String     // "I'd like to drink something"
        let audioName: String?
        let audioUrl: URL?

        init(id: String, text: String, highlightPrefix: String, translation: String, audioName: String? = nil, audioUrl: URL? = nil) {
            self.id = id
            self.text = text
            self.highlightPrefix = highlightPrefix
            self.translation = translation
            self.audioName = audioName
            self.audioUrl = audioUrl
        }
    }
}

// MARK: - Mock

enum LectureExtras {

    /// Мок под Figma 373:2487. TODO: заменить на fetch с бэка.
    static func mockKeyPhrases(for language: LanguageCode) -> [KeyPhrase] {
        switch language {
        case .es:
            return [
                KeyPhrase(id: "kp1", native: "Hola, ¿qué tal?", translation: "Hello, how are you?", audioName: nil),
                KeyPhrase(id: "kp2", native: "¿Cómo te llamas?", translation: "What's your name?", audioName: nil),
                KeyPhrase(id: "kp3", native: "Mucho gusto",     translation: "Nice to meet you", audioName: nil)
            ]
        case .en:
            return [
                KeyPhrase(id: "kp1", native: "Hi, how's it going?", translation: "Casual greeting", audioName: nil),
                KeyPhrase(id: "kp2", native: "What's your name?",    translation: "Ask their name", audioName: nil),
                KeyPhrase(id: "kp3", native: "Nice to meet you",     translation: "Polite acknowledgement", audioName: nil)
            ]
        }
    }

    static func mockPatterns(for language: LanguageCode) -> [PatternExample] {
        switch language {
        case .es:
            return [
                PatternExample(
                    id: "pt1",
                    formula: "me gustaría + infinitive",
                    examples: [
                        PatternExample.Example(
                            id: "ex1",
                            text: "Me gustaría beber algo",
                            highlightPrefix: "Me gustaría",
                            translation: "I'd like to drink something",
                            audioName: nil
                        ),
                        PatternExample.Example(
                            id: "ex2",
                            text: "Me gustaría ir al cine",
                            highlightPrefix: "Me gustaría",
                            translation: "I'd like to go to the cinema",
                            audioName: nil
                        )
                    ]
                )
            ]
        case .en:
            return [
                PatternExample(
                    id: "pt1",
                    formula: "would like + infinitive",
                    examples: [
                        PatternExample.Example(
                            id: "ex1",
                            text: "I would like to drink something",
                            highlightPrefix: "I would like",
                            translation: "Polite request",
                            audioName: nil
                        ),
                        PatternExample.Example(
                            id: "ex2",
                            text: "I would like to go to the cinema",
                            highlightPrefix: "I would like",
                            translation: "Suggestion",
                            audioName: nil
                        )
                    ]
                )
            ]
        }
    }
}
