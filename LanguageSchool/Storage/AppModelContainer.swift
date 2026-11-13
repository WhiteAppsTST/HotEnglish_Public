import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            UserEntity.self,
            LearningProfileEntity.self,
            TeacherRelationshipEntity.self
        ])
        let config = ModelConfiguration("LanguageSchool", schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // TODO: перед релизом заменить на VersionedSchema + SchemaMigrationPlan.
            print("SwiftData load failed — wiping store. Error: \(error)")
            wipePersistentStores()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create SwiftData container after wipe: \(error)")
            }
        }
    }()

    private static func wipePersistentStores() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let items = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
        for url in items {
            let name = url.lastPathComponent
            // .store, .store-shm, .store-wal, .sqlite и т.п. — сносим всё что похоже на sql-стор
            if name.contains(".store") || name.hasSuffix(".sqlite") || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".sqlite-wal") {
                try? fm.removeItem(at: url)
            }
        }
    }
}
