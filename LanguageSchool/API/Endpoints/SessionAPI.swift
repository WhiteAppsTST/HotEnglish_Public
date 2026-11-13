import Foundation

// MARK: - DTOs (по OpenAPI-схеме)

/// `SessionAttemptOut` — плоское описание попытки.
struct SessionAttemptOutDTO: Decodable {
    let id: String
    let userId: String?
    let languageCode: String
    let unitId: String
    let stepId: String
    let teacher: String
    let kind: String?
    let status: String?
    let contentVersion: Int?
    let startedAt: Date?
    let endedAt: Date?
    let durationSeconds: Int
    let score: Int?
    let communicationScore: Int?
    let completed: Bool
    let affinityDelta: Int?
    let updatedAt: Date?
}

/// Ответ `POST /session-attempts` — попытка + актуальная talk-quota.
struct SessionStartResponseDTO: Decodable {
    let attempt: SessionAttemptOutDTO
    let talkQuota: TalkQuotaDTO
}

/// `ProgressDelta` — что поменялось в прогрессе после финиша.
/// `teacherHearts` / `heartWon` — опциональные, сервер их может не прислать.
struct ProgressDeltaDTO: Decodable {
    let stepCompleted: Bool
    let unitCompleted: Bool
    let currentUnitId: String?
    let currentStepId: String?
    let lessonsCount: Int
    let averageScore: Int
    let totalSecondsSpoken: Int
    let currentStreak: Int
    let teacherAffinity: Int
    let teacherHearts: Int?
    let heartWon: Bool?
    let lessonsUntilNextHeart: Int?
}

struct SessionFinishResponseDTO: Decodable {
    let attempt: SessionAttemptOutDTO
    let progress: ProgressDeltaDTO
}

struct TalkQuotaDTO: Decodable {
    let remainingToday: Int?
    let dailyLimit: Int?
    let usedToday: Int
    let resetsAt: Date
}

struct SessionAttemptHistoryPage: Decodable {
    let items: [SessionAttemptOutDTO]
    let nextCursor: String?
}

// MARK: - Endpoints

@MainActor
enum SessionAPI {

    struct StartAttempt: Encodable {
        let id: String
        let languageCode: String
        let unitId: String
        let stepId: String
        let teacher: String
        var startedAt: Date?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(languageCode, forKey: .languageCode)
            try c.encode(unitId, forKey: .unitId)
            try c.encode(stepId, forKey: .stepId)
            try c.encode(teacher, forKey: .teacher)
            try c.encodeIfPresent(startedAt, forKey: .startedAt)
        }

        enum CodingKeys: String, CodingKey {
            case id, languageCode, unitId, stepId, teacher, startedAt
        }
    }
    /// `POST /v1/me/session-attempts` — Start.
    /// Server contract: `201` с телом `{attempt, talkQuota}` для новой попытки,
    /// `200` БЕЗ тела для идемпотентного replay-а с тем же `id`. Поэтому
    /// возвращаем optional и не падаем на пустое тело.
    static func start(_ body: StartAttempt) async throws -> SessionStartResponseDTO? {
        let raw = try await APIClient.shared.sendRaw(.POST, "/v1/me/session-attempts", body: body)
        guard !raw.data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIDateCoders.decodeStrategy
        do {
            return try decoder.decode(SessionStartResponseDTO.self, from: raw.data)
        } catch {
            // Тело пришло, но не парсится — не рушим весь flow, сервер
            // попытку принял (2xx). Отдаём nil как "серверный старт есть,
            // данных нет".
            return nil
        }
    }

    struct FinishAttempt: Encodable {
        var endedAt: Date?
        var durationSeconds: Int?
        var completed: Bool?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(endedAt, forKey: .endedAt)
            try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
            try c.encodeIfPresent(completed, forKey: .completed)
        }

        enum CodingKeys: String, CodingKey {
            case endedAt, durationSeconds, completed
        }
    }
    static func finish(id: String, _ body: FinishAttempt) async throws -> SessionFinishResponseDTO {
        try await APIClient.shared.send(.PATCH, "/v1/me/session-attempts/\(id)", body: body)
    }

    static func history(cursor: String? = nil, limit: Int = 50) async throws -> SessionAttemptHistoryPage {
        var q: [String: String] = ["limit": "\(limit)"]
        if let cursor { q["cursor"] = cursor }
        return try await APIClient.shared.send(.GET, "/v1/me/session-attempts", query: q)
    }

    static func talkQuota() async throws -> TalkQuotaDTO {
        try await APIClient.shared.send(.GET, "/v1/me/talk-quota")
    }
}
