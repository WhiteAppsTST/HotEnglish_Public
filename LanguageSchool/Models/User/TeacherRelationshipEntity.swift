import Foundation
import SwiftData

@Model
final class TeacherRelationshipEntity {
    @Attribute(.unique) var id: UUID
    var user: UserEntity?

    var teacher: TeacherProfile
    var languageCode: LanguageCode

    /// 0…100 internally; UI shows `affinity / 20` hearts.
    var affinity: Int
    var lessonsTogether: Int
    var lastInteractionAt: Date
    var updatedAt: Date

    /// JSON-кодированная история Talk-чата этой пары ([AIMessage]).
    /// Chat Completions API stateless — историю храним на клиенте.
    var talkHistoryJSON: String?

    /// Количество непрочитанных ответов ассистента в Talk. Показывается бейджем
    /// на Home. Инкрементится при получении новой реплики, ресетится при
    /// открытии Talk-экрана.
    var talkUnreadCount: Int

    init(
        id: UUID = UUID(),
        teacher: TeacherProfile,
        languageCode: LanguageCode,
        affinity: Int = 0,
        lessonsTogether: Int = 0,
        lastInteractionAt: Date = .now,
        updatedAt: Date = .now,
        talkHistoryJSON: String? = nil,
        talkUnreadCount: Int = 0
    ) {
        self.id = id
        self.teacher = teacher
        self.languageCode = languageCode
        self.affinity = affinity
        self.lessonsTogether = lessonsTogether
        self.lastInteractionAt = lastInteractionAt
        self.updatedAt = updatedAt
        self.talkHistoryJSON = talkHistoryJSON
        self.talkUnreadCount = talkUnreadCount
    }

    var heartsForUI: Int { min(5, max(0, affinity / 20)) }

    /// Стадия отношений — производная от `affinity` (0..100).
    /// Используется для UI-хинтов (стадия рядом с прогресс-баром), для
    /// выбора реакций teacher, будущей смены idle-видео.
    /// ТЗ (sec_282): «Флирт-обёртка тренажёров — реакция на каждый ответ,
    /// двигается ближе и тд.»
    var stage: TeacherStage { TeacherStage.from(affinity: affinity) }
}

/// Стадии отношений с учительницей. ТЗ описывает прогрессию как «стандартная
/// поза → флиртует → садится ближе → снимает пиджак и т. д.» — маппим на
/// 4 корзины по проценту `affinity`.
nonisolated
enum TeacherStage: String, CaseIterable, Sendable {
    /// 0..19% — знакомство, официальный тон.
    case neutral
    /// 20..49% — юзер завёл симпатию, лёгкая теплота.
    case warmingUp
    /// 50..79% — реальный интерес, флирт-реплики становятся заметнее.
    case flirting
    /// 80..100% — близость, teacher максимально открыта.
    case close

    static func from(affinity: Int) -> TeacherStage {
        let clamped = max(0, min(100, affinity))
        switch clamped {
        case ..<20:   return .neutral
        case 20..<50: return .warmingUp
        case 50..<80: return .flirting
        default:      return .close
        }
    }

    var localizedTitle: String {
        switch self {
        case .neutral:   return L10n.tr("affinity.stage.cold",       "cold")
        case .warmingUp: return L10n.tr("affinity.stage.warming_up", "warming up")
        case .flirting:  return L10n.tr("affinity.stage.sympathy",   "sympathy")
        case .close:     return L10n.tr("affinity.stage.close",      "close")
        }
    }
}
