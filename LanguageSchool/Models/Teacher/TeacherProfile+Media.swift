import Foundation

/// Медиа-каталог учительницы: видео и аудио файлы для разных контекстов.
///
/// Все файлы лежат в `LanguageSchool/Resources/Avatars/` в кириллических
/// папках `{Эмма|Ария|Мия|Шарлотта|Юки}/…`, но `Bundle.main.url(forResource:)`
/// плоско резолвит по имени файла, так что папки роли не играют.
///
/// Именование строго: `{TeacherName}_{StateRawValue}` для lesson/dating/sound,
/// `{TeacherName}_Choose(SP|US)` для choose-войсов. Опечатка «Iddle» сохранена
/// в rawValue (так называются файлы), но в API кейс называется `.idle`.
///
/// TODO: когда бэк начнёт отдавать URL-ы (или разные наборы под юзера) —
/// заменить `Bundle.main.url` на скачанные пути / cached-URLs.
extension TeacherProfile {

    // MARK: - Lesson video states (Resources/Avatars/{Name}/{Name}_lessons/)

    /// Состояния учительницы во время урока. Файлы: `{Name}_{rawValue}.mp4`.
    nonisolated
    enum LessonState: String, CaseIterable, Sendable {
        case idle          = "Iddle"          // typo в файлах сохранён
        case listening     = "Listening"
        case talking       = "Talking"
        case correctAnswer = "Correct_Answer"
        case wrongAnswer   = "Wrong_Answer"
        case flirting      = "Flirting"
    }

    /// URL видео для указанного lesson-состояния (или nil если файл не в бандле).
    func lessonVideo(_ state: LessonState) -> URL? {
        Bundle.main.url(forResource: "\(name)_\(state.rawValue)", withExtension: "mp4")
    }

    // MARK: - Dating video states (Resources/Avatars/{Name}/{Name}_dating/)

    /// Состояния для экрана свидания (открывается после completion юнита,
    /// «Date with Emma ♡»). Файлы: `{Name}_Dating_{rawValue}.mp4`.
    nonisolated
    enum DatingState: String, CaseIterable, Sendable {
        case idle          = "Iddle"
        case listening     = "Listening"
        case talking       = "Talking"
        case flirting      = "Flirting"
        case softFlirting  = "Soft_Flirting"
        case badReaction   = "Bad_Reaction"
        case goodEnding    = "Good_Ending"
        case neutralEnding = "Neutral_Ending"
    }

    /// URL видео для указанного dating-состояния.
    func datingVideo(_ state: DatingState) -> URL? {
        Bundle.main.url(forResource: "\(name)_Dating_\(state.rawValue)", withExtension: "mp4")
    }

    // MARK: - Short sound effects (Resources/Avatars/{Name}/{Name}_sound/)

    /// Короткие SFX (не голос-фразы) — эмоциональная озвучка (mp3).
    /// Файлы: `{Name}_{rawValue}.mp3`.
    nonisolated
    enum SoundEffect: String, CaseIterable, Sendable {
        case flirting = "Flirting"
        case smile    = "Smile"
        case thinking = "Thinking"
    }

    /// URL звукового эффекта учительницы.
    func sound(_ effect: SoundEffect) -> URL? {
        Bundle.main.url(forResource: "\(name)_\(effect.rawValue)", withExtension: "mp3")
    }

    // MARK: - Choose screen (Resources/Avatars/2.Экран выбора девушки/{Name}_Choose/)

    /// Preview-видео учительницы на экране выбора (`AssistenceSelectionView`).
    /// Файл: `{Name}_Choose.mp4`.
    var chooseVideo: URL? {
        Bundle.main.url(forResource: "\(name)_Choose", withExtension: "mp4")
    }

    /// Приветственный голосовой семпл учительницы на языке обучения.
    /// - `.es` → `{Name}_Choose(SP).mp3`
    /// - `.en` → `{Name}_Choose(US).mp3`
    func chooseVoice(for language: LanguageCode) -> URL? {
        let suffix: String = {
            switch language {
            case .es: return "(SP)"
            case .en: return "(US)"
            }
        }()
        return Bundle.main.url(forResource: "\(name)_Choose\(suffix)", withExtension: "mp3")
    }
}
