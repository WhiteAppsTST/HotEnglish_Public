import Foundation

@MainActor
enum DevicesAPI {

    struct RegisterDevice: Encodable {
        let apnsToken: String
        var platform: String = "ios"
        var locale: String?
        var timezone: String?
        var appVersion: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(apnsToken, forKey: .apnsToken)
            try c.encode(platform, forKey: .platform)
            try c.encodeIfPresent(locale, forKey: .locale)
            try c.encodeIfPresent(timezone, forKey: .timezone)
            try c.encodeIfPresent(appVersion, forKey: .appVersion)
        }

        enum CodingKeys: String, CodingKey {
            case apnsToken, platform, locale, timezone, appVersion
        }
    }
    static func register(_ body: RegisterDevice) async throws {
        _ = try await APIClient.shared.send(.POST, "/v1/me/devices", body: body)
    }

    static func unregister(token: String) async throws {
        _ = try await APIClient.shared.send(.DELETE, "/v1/me/devices/\(token)")
    }
}
