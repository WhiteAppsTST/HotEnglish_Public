import Foundation

/// Оркестратор загрузки курса. Двухфазный:
///  1. Синхронно отдаёт кэшированный bundle (если есть) — UI показывает
///     старый курс мгновенно.
///  2. Асинхронно уходит в бэк с `If-None-Match` — при `200` перезаписывает
///     кэш и вью зовёт refresh; при `304` ничего не делает.
///
/// Изоляция @MainActor — потому что консюмеры (HomeViewModel) тоже
/// @MainActor. Никаких background очередей — вся синхронизация вокруг
/// `bundle(for:)`.
@MainActor
final class ContentService {

    static let shared = ContentService()
    private init() {}

    /// Немедленный доступ к кэшу без сети. `nil` — кэша ещё нет.
    func cachedBundle(for lang: LanguageCode) -> ContentBundleDTO? {
        ContentCache.read(lang: lang.rawValue)?.0
    }

    /// Свежий bundle: сначала пробуем сервер (с ETag), при неудаче возвращаем
    /// кэш. Возвращает `true` во втором значении когда данные пришли свежие
    /// с сервера — вью может понадобиться прогреть аудио-кэш.
    @discardableResult
    func fetchBundle(
        for lang: LanguageCode,
        level: LangGrade? = nil
    ) async -> (ContentBundleDTO?, Bool) {
        let cached = ContentCache.read(lang: lang.rawValue)
        do {
            let result = try await ContentAPI.bundle(
                lang: lang.rawValue,
                level: level?.rawValue,
                ifNoneMatch: cached?.1
            )
            switch result {
            case .fresh(let dto, let etag, let raw):
                ContentCache.write(lang: lang.rawValue, rawJSON: raw, etag: etag)
                return (dto, true)
            case .notModified:
                return (cached?.0, false)
            }
        } catch {
            // Сеть/декодер — возвращаем то что было в кэше, чтобы юзер
            // мог продолжать заниматься.
            return (cached?.0, false)
        }
    }
}
