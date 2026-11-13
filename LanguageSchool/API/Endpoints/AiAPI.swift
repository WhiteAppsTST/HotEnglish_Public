import Foundation

// MARK: - DTOs (по OpenAPI v1/openapi.json)

/// `POST /v1/ai/evaluate-reply` → `EvaluateReplyResponse`
struct EvaluateReplyDTO: Decodable {
    let score: Int              // 0…100
    let matchedIntent: String
    let feedback: String
    let correctionText: String
    let usedFallback: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.score          = try c.decode(Int.self,    forKey: .score)
        self.matchedIntent  = try c.decode(String.self, forKey: .matchedIntent)
        self.feedback       = try c.decode(String.self, forKey: .feedback)
        self.correctionText = try c.decode(String.self, forKey: .correctionText)
        self.usedFallback   = try c.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
    }
    enum CodingKeys: String, CodingKey {
        case score, matchedIntent, feedback, correctionText, usedFallback
    }
}

/// `POST /v1/ai/chat-turn` → `ChatTurnResponse`
struct ChatTurnDTO: Decodable {
    let teacherText: String
    let translation: String
    let correctionText: String      // default ""
    let correctionNote: String      // default ""
    let audioUrl: URL?
    let shouldEnd: Bool
    let turnIndex: Int
    let elapsedSeconds: Int
    let usedFallback: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.teacherText    = try c.decode(String.self, forKey: .teacherText)
        self.translation    = try c.decode(String.self, forKey: .translation)
        self.correctionText = try c.decodeIfPresent(String.self, forKey: .correctionText) ?? ""
        self.correctionNote = try c.decodeIfPresent(String.self, forKey: .correctionNote) ?? ""
        if let s = try c.decodeIfPresent(String.self, forKey: .audioUrl) {
            self.audioUrl = URL(string: s)
        } else {
            self.audioUrl = nil
        }
        self.shouldEnd      = try c.decode(Bool.self, forKey: .shouldEnd)
        self.turnIndex      = try c.decode(Int.self,  forKey: .turnIndex)
        self.elapsedSeconds = try c.decode(Int.self,  forKey: .elapsedSeconds)
        self.usedFallback   = try c.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
    }
    enum CodingKeys: String, CodingKey {
        case teacherText, translation, correctionText, correctionNote,
             audioUrl, shouldEnd, turnIndex, elapsedSeconds, usedFallback
    }
}

/// `POST /v1/ai/evaluate-session` → `EvaluateSessionResponse`
struct EvaluateSessionDTO: Decodable {
    let score: Int                   // 0…100
    let communicationScore: Int      // 0…100
    let affinityDelta: Int
    let highlights: [String]
    let suggestions: [String]
    let teacherAffinity: Int
    let usedFallback: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.score              = try c.decode(Int.self,       forKey: .score)
        self.communicationScore = try c.decode(Int.self,       forKey: .communicationScore)
        self.affinityDelta      = try c.decode(Int.self,       forKey: .affinityDelta)
        self.highlights         = try c.decode([String].self,  forKey: .highlights)
        self.suggestions        = try c.decode([String].self,  forKey: .suggestions)
        self.teacherAffinity    = try c.decode(Int.self,       forKey: .teacherAffinity)
        self.usedFallback       = try c.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
    }
    enum CodingKeys: String, CodingKey {
        case score, communicationScore, affinityDelta,
             highlights, suggestions, teacherAffinity, usedFallback
    }
}

/// `GET /v1/me/teachers/{teacher}/daily-quote` → `DailyQuoteResponse`
struct DailyQuoteDTO: Decodable {
    let text: String
    let generatedAt: Date
    let expiresAt: Date
}

// MARK: - Endpoints

@MainActor
enum AiAPI {

    struct EvaluateReplyBody: Encodable {
        struct Input: Encodable {
            let text: String
            var audioKey: String?
        }
        let sessionAttemptId: String
        let exchangeId: String
        let userInput: Input
    }
    static func evaluateReply(_ body: EvaluateReplyBody) async throws -> EvaluateReplyDTO {
        try await APIClient.shared.send(.POST, "/v1/ai/evaluate-reply", body: body)
    }

    struct ChatTurnBody: Encodable {
        let sessionAttemptId: String
        let userText: String
    }
    static func chatTurn(_ body: ChatTurnBody) async throws -> ChatTurnDTO {
        try await APIClient.shared.send(.POST, "/v1/ai/chat-turn", body: body)
    }

    struct TranscriptLine: Encodable {
        let role: String        // "user" | "teacher"
        let text: String
        var audioUrl: String?
    }
    struct EvaluateSessionBody: Encodable {
        let sessionAttemptId: String
        var transcript: [TranscriptLine]?
    }
    static func evaluateSession(_ body: EvaluateSessionBody) async throws -> EvaluateSessionDTO {
        try await APIClient.shared.send(.POST, "/v1/ai/evaluate-session", body: body)
    }

    static func dailyQuote(teacher: String) async throws -> DailyQuoteDTO {
        try await APIClient.shared.send(.GET, "/v1/me/teachers/\(teacher)/daily-quote")
    }

    // MARK: - TTS

    /// Запрос к `POST /v1/ai/tts`: text → аудио-URL в голосе выбранного учителя.
    /// Используется для озвучки реплик, которые бэк не рождает сам —
    /// локального opener'а и клиентских GPT-ответов (когда серверный
    /// `chat-turn` отказал 409 на speaking-степах).
    struct TTSBody: Encodable {
        let text: String
        let teacher: String   // TeacherProfile.rawValue, напр. "yuki"
        let language: String  // LanguageCode.rawValue, напр. "en"
    }
    struct TTSDTO: Decodable {
        let audioUrl: URL?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try c.decodeIfPresent(String.self, forKey: .audioUrl) {
                self.audioUrl = URL(string: s)
            } else {
                self.audioUrl = nil
            }
        }
        enum CodingKeys: String, CodingKey { case audioUrl }
    }
    static func tts(_ body: TTSBody) async throws -> TTSDTO {
        try await APIClient.shared.send(.POST, "/v1/ai/tts", body: body)
    }
}
