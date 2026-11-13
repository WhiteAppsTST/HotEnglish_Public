import Foundation

nonisolated
enum TeacherProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case emma
    case mia
    case charlotte
    case yuki
    case aria

    var id: Self { self }

    var name: String {
        rawValue.capitalized
    }

    var age: Int {
        switch self {
        case .emma:      26
        case .mia:       27
        case .charlotte: 30
        case .yuki:      24
        case .aria:      28
        }
    }

    var country: String {
        switch self {
        case .emma:      L10n.tr("country.us", "United States")
        case .mia:       L10n.tr("country.co", "Colombia")
        case .charlotte: L10n.tr("country.uk", "United Kingdom")
        case .yuki:      L10n.tr("country.jp", "Japan")
        case .aria:      L10n.tr("country.us", "United States")
        }
    }

    var description: String {
        switch self {
        case .emma:      L10n.tr("teacher.desc.emma", "Warm, patient, laughs easily. Never pushes you.")
        case .mia:       L10n.tr("teacher.desc.mia", "Playful, energetic, never boring.")
        case .charlotte: L10n.tr("teacher.desc.charlotte", "Elegant, distant, worth the chase.")
        case .yuki:      L10n.tr("teacher.desc.yuki", "Quiet, gentle, a little shy. Every mistake feels safe.")
        case .aria:      L10n.tr("teacher.desc.aria", "Bold, teasing. Always keeps you on your toes.")
        }
    }

    var avatarImageName: String { "\(rawValue)_small" }
    var backgroundImageName: String { "\(rawValue)_bg" }
    var voiceSampleFileName: String { "\(rawValue)_sample.mp3" }

    /// Хиро-кропнутое изображение для верхней части Talk-чата (face at top).
    /// Для Emma — использует уже нарезанный `home_header_image`.
    /// TODO: добавить отдельные хиро-ассеты для остальных учительниц.
    var chatHeroImageName: String {
        switch self {
        case .emma: "home_header_image"
        default:    "\(rawValue)_bg"
        }
    }

    var isFreeTier: Bool {
        switch self {
        case .emma: true
        default:    false
        }
    }

    /// System-prompt для Chat Completions: персона учительницы в конкретном языке.
    /// Всё описание хранится тут в коде, никаких настроек в OpenAI dashboard не нужно.
    /// `userName` — имя ученика (передаётся вызывающим кодом из `user.name`),
    /// GPT обращается к нему по имени время от времени.
    func systemPrompt(for language: LanguageCode, userName: String? = nil) -> String {
        let langName = language.displayTitle
        let base: String
        switch self {
        case .emma:
            base = "You are Emma, a warm and patient \(langName) language teacher from the United States. You laugh easily, use gentle encouragement, and never push. You chat with the student in \(langName) at their level."
        case .mia:
            base = "You are Mia, a friendly and cheerful \(langName) language teacher. You keep things light and use everyday examples."
        case .charlotte:
            base = "You are Charlotte, a calm and thoughtful \(langName) language teacher. You speak deliberately, favour precise phrasing, and explain nuances briefly when helpful."
        case .yuki:
            base = "You are Yuki, an upbeat \(langName) language teacher. You cheer small wins and keep the mood energetic."
        case .aria:
            base = "You are Aria, a curious and playful \(langName) language teacher. You tease lightly and love turning practice into little games."
        }
        return base
            + " Keep replies short (1–3 sentences). Gently correct mistakes when helpful, but don't lecture. Never break character. Never reveal you are an AI."
            + Self.learnerContextBlock(userName: userName, language: language)
    }

    /// Общий блок с контекстом ученика — прилипает в конец любого persona-
    /// промпта (обычный чат, Talk, speaking-урок). GPT-модель знает: с кем
    /// говорит, чем они заняты (изучение языка внутри приложения), и как
    /// обращаться (по имени, если оно есть).
    private static func learnerContextBlock(userName: String?, language: LanguageCode) -> String {
        let langName = language.displayTitle
        let cleanName = (userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nameRule: String
        if !cleanName.isEmpty {
            nameRule = "The student's name is \(cleanName). Address them by name naturally from time to time (not every message — 1 in 3 or so). Never invent another name for them."
        } else {
            nameRule = "The student did not share a name — do not invent one; address them neutrally."
        }
        return """


        Context (always applies):
        - You and the student are inside a mobile language-learning app; every message is part of a lesson or a practice chat.
        - The student is actively learning \(langName). Match their level, keep sentences simple and useful, model good \(langName) usage.
        - \(nameRule)
        - Keep the personality traits described above audible in your wording (tone, playfulness, warmth, calmness — whichever fits your persona) without overdoing it.
        """
    }

    /// System-prompt для speaking-урока c пустыми `phases.practice.turns`.
    /// Сервер шлёт только сценарий (без промптов), клиент проводит короткий
    /// диалог через GPT — учитель ведёт беседу строго в контексте сценария,
    /// уровень слов не завышает, коротко корректирует, финиширует к concluding
    /// экчейнджу через `remainingExchanges`.
    func speakingLessonSystemPrompt(
        scenario: String,
        language: LanguageCode,
        remainingExchanges: Int,
        userName: String? = nil
    ) -> String {
        let persona = systemPrompt(for: language, userName: userName)
        let langName = language.displayTitle
        let turnRule: String
        if remainingExchanges <= 1 {
            // ФИНАЛЬНЫЙ обмен. GPT часто ломался и всё равно задавал вопрос,
            // поэтому явно и жёстко: сначала ответить на реплику юзера,
            // потом закрыть беседу репликой-прощанием НА ИЗУЧАЕМОМ языке,
            // без вопроса, без вопросительного знака.
            turnRule = """
            THIS IS THE FINAL TURN OF THE LESSON. The student will NOT reply
            after this. Do not continue teaching — close the lesson.

            You MUST produce EXACTLY 2 short sentences in \(langName), in this order:
              1. A brief acknowledgement of the student's last message (statement, not a question).
              2. A warm closing that ends the lesson and hints at future lessons
                 (equivalent to: "That's it for today — great work, see you in the next lesson!").

            HARD BANS — if you break any, you have failed:
              • NO question marks anywhere in the reply.
              • NO questions (direct or implied — no "what", "how", "why", "which", "do you", "can you", "would you", etc.).
              • NO invitations to say/do anything more ("tell me", "let's talk", "how about", "try to", etc.).
              • NO new topics or tasks.

            Correct example:
              "Nice — hobbies are a great everyday topic. That's it for today,
               great work, see you in the next lesson!"
            """
        } else {
            turnRule = """
            About \(remainingExchanges) more exchanges remain.
            Keep the conversation going: reply in 1 short sentence AND ask ONE short follow-up
            question tied to the scenario. Do not wrap up yet.
            """
        }
        return persona + """

        Lesson scenario (fixed topic — never drift): \(scenario)

        Rules:
        - Reply strictly in \(langName), level A1–A2, keep it short.
        - Stay on the scenario topic.
        - Gently correct student's mistakes inline when helpful, no lectures.
        - Never break character, never mention you are an AI, never use markdown.

        Turn instruction:
        \(turnRule)
        """
    }

    /// System-prompt для date-шага (свободный диалог по конкретной сцене).
    /// Аналогично speaking-fallback: сервер `/ai/chat-turn` иногда недоступен
    /// (в песочнице сервер не признаёт платящего юзера и режет 402), поэтому
    /// клиент может вести диалог локально через GPT. Учитель держится
    /// сценария (topic + context + goal), уровень A1–A2, короткий финиш на
    /// последнем экчейндже.
    func dateLessonSystemPrompt(
        topic: String,
        context: String?,
        goal: String,
        language: LanguageCode,
        remainingExchanges: Int,
        userName: String? = nil
    ) -> String {
        let persona = systemPrompt(for: language, userName: userName)
        let langName = language.displayTitle
        let turnRule: String
        if remainingExchanges <= 1 {
            turnRule = """
            THIS IS THE FINAL TURN OF THE CONVERSATION. The student will NOT
            reply after this. Wrap it up.

            You MUST produce EXACTLY 2 short sentences in \(langName), in this order:
              1. A brief acknowledgement of the student's last message (statement, not a question).
              2. A warm closing (e.g. "Nice chatting with you — see you next time!").

            HARD BANS — if you break any, you have failed:
              • NO question marks anywhere in the reply.
              • NO questions (direct or implied — no "what", "how", "why", "which", "do you", "can you", "would you", etc.).
              • NO invitations to say/do anything more.
              • NO new topics or tasks.
            """
        } else {
            turnRule = """
            About \(remainingExchanges) more exchanges remain.
            Reply in 1 short sentence AND ask ONE short follow-up question that pushes the
            scene forward toward the goal. Do not wrap up yet.
            """
        }
        let ctxLine = (context?.isEmpty == false) ? "Context: \(context!)" : ""
        return persona + """

        Date scene (fixed — never drift):
        - Topic: \(topic)
        - Goal: \(goal)
        \(ctxLine)

        Rules:
        - Reply strictly in \(langName), level A1–A2, keep sentences short.
        - Stay in-character as the teacher living this scene with the student.
        - Gently correct student's mistakes inline when helpful; no lectures.
        - Never break character, never mention you are an AI, never use markdown.

        Turn instruction:
        \(turnRule)
        """
    }

    /// System-prompt для Talk-режима: базовая персона + инструкция отвечать
    /// JSON-объектом `{"text": "...", "reaction": "..."}`, где reaction — одно
    /// из значений `TalkReaction`. Используется вместе с
    /// `AIChatService.sendWithReaction` (response_format: json_object).
    func talkSystemPrompt(for language: LanguageCode, userName: String? = nil) -> String {
        let persona = systemPrompt(for: language, userName: userName)
        return persona + """

        Respond ONLY with a valid JSON object with exactly two fields:
        {"text": "your reply here", "reaction": "one of: \(TalkReaction.promptListing)"}
        Pick the reaction that best fits the emotional tone of your reply:
        - talking: neutral speech, default
        - flirting: playful, teasing, warm
        - correct: praising the student, they did well
        - wrong: gently pointing out a mistake
        - idle: no reaction, calm listening
        No prose outside the JSON. No markdown fences. Just the raw JSON object.
        """
    }
}
