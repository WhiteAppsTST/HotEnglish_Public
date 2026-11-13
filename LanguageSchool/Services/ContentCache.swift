import Foundation

/// Дисковый кэш ответа `/v1/content/{lang}` — ETag + JSON-body.
///
/// Хранится в `Application Support/content/{lang}.json` и `.etag`.
/// Один файл на язык: перезапись атомарная, коррупция при вылете исключена.
///
/// Клиент показывает контент из кэша сразу на старте (без задержки на сеть),
/// параллельно уходит с `If-None-Match` за обновлением. При `304` — ничего не
/// делаем; при `200` — перезаписываем оба файла.
enum ContentCache {

    /// Читать кэш, если есть. Возвращает `(bundle, etag)` или nil.
    static func read(lang: String) -> (ContentBundleDTO, String)? {
        guard let dir = dir() else { return nil }
        let bodyURL = dir.appendingPathComponent("\(lang).json")
        let etagURL = dir.appendingPathComponent("\(lang).etag")
        guard let data = try? Data(contentsOf: bodyURL),
              let etag = (try? Data(contentsOf: etagURL)).flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIDateCoders.decodeStrategy
        guard let bundle = try? decoder.decode(ContentBundleDTO.self, from: data)
        else { return nil }
        return (bundle, etag)
    }

    /// Атомарно записать свежие body+etag.
    static func write(lang: String, rawJSON: Data, etag: String) {
        guard let dir = dir() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bodyURL = dir.appendingPathComponent("\(lang).json")
        let etagURL = dir.appendingPathComponent("\(lang).etag")
        try? rawJSON.write(to: bodyURL, options: .atomic)
        try? Data(etag.utf8).write(to: etagURL, options: .atomic)
    }

    /// Стереть кэш всех языков (например при logout).
    static func clear() {
        guard let dir = dir() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private static func dir() -> URL? {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base?.appendingPathComponent("content", isDirectory: true)
    }
}
