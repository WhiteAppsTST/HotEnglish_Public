import Foundation
import SwiftData

@MainActor
final class UserRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Read

    func currentUser() -> UserEntity? {
        let descriptor = FetchDescriptor<UserEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    func find(externalAuthId: String, provider: AuthProvider) -> UserEntity? {
        // Predicates on custom Codable enums are fragile in SwiftData —
        // narrow by the String field, then filter in Swift.
        let descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate { $0.externalAuthId == externalAuthId }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { $0.provider == provider }
    }

    // MARK: - Write

    /// Fetch existing user by (provider, externalAuthId) or create a fresh one
    /// with sensible defaults. Does not overwrite any onboarding state.
    @discardableResult
    func upsert(from authUser: AuthUser) -> UserEntity {
        if let existing = find(externalAuthId: authUser.id, provider: authUser.provider) {
            var didChange = false
            if let email = authUser.email, existing.email != email {
                existing.email = email; didChange = true
            }
            if let name = authUser.name, !name.isEmpty, existing.name != name {
                existing.name = name; didChange = true
            }
            if let avatar = authUser.profileImageUrl, existing.avatarURL != avatar {
                existing.avatarURL = avatar; didChange = true
            }
            if didChange {
                existing.updatedAt = .now
                try? context.save()
            }
            return existing
        }

        let fresh = UserEntity(
            externalAuthId: authUser.id,
            provider: authUser.provider,
            email: authUser.email,
            name: authUser.name ?? "",
            avatarURL: authUser.profileImageUrl
        )
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    /// Зеркалит серверный документ юзера в SwiftData. Сервер — источник
    /// правды: settings, learning-profiles, teacher-relationships, streak,
    /// isPremium — всё переписывается тем, что пришло в `MeDTO`.
    @discardableResult
    func upsert(from me: MeDTO, provider: AuthProvider) -> UserEntity {
        MeMapper.upsert(me, provider: provider, in: context)
    }

    func save() {
        do { try context.save() } catch { assertionFailure("SwiftData save failed: \(error)") }
    }

    func delete(_ user: UserEntity) {
        context.delete(user)
        try? context.save()
    }
}
