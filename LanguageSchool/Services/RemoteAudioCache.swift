import Foundation

/// Дисковый кэш для аудио-файлов с сервера. Сервер гарантирует, что имя
/// файла = хеш содержимого, значит по одному URL всегда одни и те же байты —
/// можно кэшировать сколько угодно.
///
/// Кладём в `Caches/remote-audio/` (система сама может почистить при
/// нехватке места — это правильно для аудио-ассетов).
enum RemoteAudioCache {

    /// Отдать локальный URL по удалённому. Если файла нет — скачивает.
    /// Возвращает nil при ошибке (сеть, некорректный URL) — вызывающий
    /// сам решает как реагировать (у нас — просто не играем).
    static func localURL(for remote: URL) async -> URL? {
        guard let dir = ensureCacheDir() else { return nil }
        let filename = remote.lastPathComponent.isEmpty ? remote.absoluteString.hashed() : remote.lastPathComponent
        let target = dir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }

    private static func ensureCacheDir() -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = caches.appendingPathComponent("remote-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private extension String {
    /// Простой sha256-ish хеш (не крипто, только для имени файла).
    func hashed() -> String {
        var h: UInt64 = 5381
        for b in self.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }
}
