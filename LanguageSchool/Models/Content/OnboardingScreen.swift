import Foundation

/// Один из 6 экранов онбординга. Каждый имеет видео (mp4) + голосовой
/// семпл (mp3) на двух языках: испанском (по умолчанию) и английском
/// (с суффиксом `_en`).
///
/// Файлы:
/// `Resources/Avatars/1.онбординг/Онбординг на испанском/{N} экран онбординга/…`
/// `Resources/Avatars/1.онбординг/Онбординг на английском/{N} экран онбординга/…`
///
/// Первый экран назван нестандартно — `Первый экран онбординга(1).mp4` для
/// видео и `Первый экран онбординга.mp3` для аудио (без `(1)`). Остальные —
/// строго `{N} экран онбординга.{mp4|mp3}`.
///
/// TODO: если появится 3+ языка — заменить `LanguageCode`-suffix на маппер.
nonisolated
enum OnboardingScreen: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, two, three, four, five, six

    var id: Int { rawValue }

    /// URL видео экрана на указанном языке обучения.
    /// Английский вариант — с суффиксом `_en` в имени файла.
    func videoURL(for language: LanguageCode) -> URL? {
        Bundle.main.url(forResource: videoBaseName(for: language), withExtension: "mp4")
    }

    /// URL голосового семпла экрана на указанном языке.
    func voiceURL(for language: LanguageCode) -> URL? {
        Bundle.main.url(forResource: audioBaseName(for: language), withExtension: "mp3")
    }

    /// Общий idle-фон для всех экранов онбординга (`Idlle.mp4` в корне
    /// папки онбординга). Опечатка «Idlle» с двойным L — сохранена как в файле.
    static var idleBackground: URL? {
        Bundle.main.url(forResource: "Idlle", withExtension: "mp4")
    }

    // MARK: - Private helpers

    private func videoBaseName(for language: LanguageCode) -> String {
        // Первый экран называется не как остальные.
        let baseES = (self == .one)
            ? "Первый экран онбординга(1)"
            : "\(rawValue) экран онбординга"
        return language == .en ? "\(baseES)_en" : baseES
    }

    private func audioBaseName(for language: LanguageCode) -> String {
        // Аудио первого экрана без `(1)` в отличие от видео.
        let baseES = (self == .one)
            ? "Первый экран онбординга"
            : "\(rawValue) экран онбординга"
        return language == .en ? "\(baseES)_en" : baseES
    }
}
