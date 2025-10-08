import Foundation
import Operation_iOS

public struct AppAttestLocalSettings: Codable {
    public let persistentId: String
    public let keyId: String
    public let isAttested: Bool

    public init(
        persistentId: String,
        keyId: String,
        isAttested: Bool
    ) {
        self.persistentId = persistentId
        self.keyId = keyId
        self.isAttested = isAttested
    }
}

extension AppAttestLocalSettings: Operation_iOS.Identifiable {
    public var identifier: String {
        persistentId
    }
}
