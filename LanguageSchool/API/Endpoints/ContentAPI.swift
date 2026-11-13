import Foundation

// MARK: - Top-level content DTOs (строго по OpenAPI)

struct ContentBundleDTO: Decodable {
    let schemaVersion: Int?
    let languageCode: String
    let version: Int?
    let translationLanguage: String?
    let level: String?
    let units: [ContentUnitDTO]
}

struct ContentUnitDTO: Decodable {
    let id: String
    let order: Int
    let level: String?
    let lessonType: String?
    let title: String
    let iconName: String?
    let isPremium: Bool?
    let difficultyLevel: Int?
    let unlockRule: UnlockRuleDTO?
    let steps: [ContentStepDTO]
}

struct ContentStepDTO: Decodable {
    let id: String
    let order: Int
    let kind: String
    let title: String
    let subtitle: String
    let difficultyLevel: Int?
    let unlockRule: UnlockRuleDTO?
    let payload: StepPayloadDTO

    private enum CodingKeys: String, CodingKey {
        case id, order, kind, title, subtitle, difficultyLevel, unlockRule, payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        order = try c.decode(Int.self, forKey: .order)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        difficultyLevel = try c.decodeIfPresent(Int.self, forKey: .difficultyLevel)
        unlockRule = try c.decodeIfPresent(UnlockRuleDTO.self, forKey: .unlockRule)

        // Полиморфный payload — сервер использует implicit discriminator по `kind`.
        switch kind {
        case "lecture":
            payload = .lecture(try c.decode(LecturePayloadDTO.self, forKey: .payload))
        case "topicWords":
            payload = .topicWords(try c.decode(TopicWordsPayloadDTO.self, forKey: .payload))
        case "pattern":
            payload = .pattern(try c.decode(PatternPayloadDTO.self, forKey: .payload))
        case "grammar":
            payload = .grammar(try c.decode(GrammarPayloadDTO.self, forKey: .payload))
        case "speaking":
            payload = .speaking(try c.decode(SpeakingPayloadDTO.self, forKey: .payload))
        case "date":
            payload = .date(try c.decode(DatePayloadDTO.self, forKey: .payload))
        default:
            payload = .unknown
        }
    }
}

// MARK: - Unlock rules

enum UnlockRuleDTO: Decodable {
    case afterUnit(String)
    case afterStep(String)

    private enum CodingKeys: String, CodingKey {
        case kind, unitId, stepId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "afterUnit":
            self = .afterUnit(try c.decode(String.self, forKey: .unitId))
        case "afterStep":
            self = .afterStep(try c.decode(String.self, forKey: .stepId))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unknown unlock rule kind '\(kind)'"
            )
        }
    }
}

// MARK: - Step payloads

enum StepPayloadDTO {
    case lecture(LecturePayloadDTO)
    case topicWords(TopicWordsPayloadDTO)
    case pattern(PatternPayloadDTO)
    case grammar(GrammarPayloadDTO)
    case speaking(SpeakingPayloadDTO)
    case date(DatePayloadDTO)
    case unknown
}

struct WordDTO: Decodable {
    let id: String
    let text: String
    let translation: String
    let imageUrl: String?
    let audioUrl: String?
}

struct PatternExampleDTO: Decodable {
    let text: String
    let translation: String
    let audioUrl: String?
}

struct LectureTurnDTO: Decodable {
    let id: String
    let teacherText: String
    let focusWordIds: [String]?
    let showPattern: Bool?
    let userReply: String?
    let audioUrl: String?
}

struct LecturePayloadDTO: Decodable {
    let words: [WordDTO]
    let pattern: PatternPayloadDTO
    let turns: [LectureTurnDTO]
}

struct TopicWordsPayloadDTO: Decodable {
    let words: [WordDTO]
}

struct PatternPayloadDTO: Decodable {
    let formula: String
    let explanation: String
    let explanationAudioUrl: String?
    let examples: [PatternExampleDTO]
}

struct GrammarExerciseDTO: Decodable {
    let id: String
    let kind: String                 // "wordOrder"
    let presentation: String?        // "fillBlank" | "listenChoice" | "wordOrder"
    let prompt: String
    let expected: [String]
    let distractors: [String]?
    let translation: String
    let audioUrl: String?
}

struct GrammarPayloadDTO: Decodable {
    let exercises: [GrammarExerciseDTO]
}

/// Фаза Speaking-урока. Точная схема Phase на сервере не задокументирована в
/// той выборке что мы вытянули — держим terpimoe DTO, декодим что есть.
struct PhaseDTO: Decodable {
    let turns: [LectureTurnDTO]?
    let scenario: String?
    let goal: String?
}

struct SpeakingPhasesDTO: Decodable {
    let lecture: PhaseDTO
    let practice: PhaseDTO
}

struct SpeakingPayloadDTO: Decodable {
    let scenario: String
    let phases: SpeakingPhasesDTO
}

struct OpeningLineDTO: Decodable {
    let text: String
    let translation: String?
    let audioUrl: String?
}

struct DatePayloadDTO: Decodable {
    let topic: String
    let context: String?
    let goal: String
    let openingLine: OpeningLineDTO
    let minDurationSeconds: Int?
    let maxDurationSeconds: Int?
}

// MARK: - Manifest

struct ContentManifestDTO: Decodable {
    let languageCode: String
    let version: Int?
    let schemaVersion: Int?
    let etag: String?
    let unitCount: Int?
    let stepCount: Int?
    let publishedAt: String?
}

// MARK: - Endpoints

@MainActor
enum ContentAPI {

    /// Курс целиком с ETag. При совпадении сервер отдаёт 304 → возвращаем
    /// `.notModified`, клиент продолжает пользоваться кэшем.
    static func bundle(
        lang: String,
        level: String? = nil,
        ifNoneMatch etag: String? = nil
    ) async throws -> ContentBundleResult {
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        var query: [String: String] = [:]
        if let level { query["level"] = level }

        let raw = try await APIClient.shared.sendRaw(
            .GET, "/v1/content/\(lang)",
            query: query,
            extraHeaders: headers
        )
        if raw.response.statusCode == 304 { return .notModified }

        let newEtag = raw.response.value(forHTTPHeaderField: "ETag") ?? ""
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = APIDateCoders.decodeStrategy
            let dto = try decoder.decode(ContentBundleDTO.self, from: raw.data)
            return .fresh(dto, etag: newEtag, rawJSON: raw.data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    static func manifest(lang: String) async throws -> ContentManifestDTO {
        try await APIClient.shared.send(.GET, "/v1/content/\(lang)/manifest")
    }
}

enum ContentBundleResult {
    case fresh(ContentBundleDTO, etag: String, rawJSON: Data)
    case notModified
}
