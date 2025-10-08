import Foundation
import Operation_iOS

public struct AppAttestConfiguration {
    /// Attestation token identifier
    public let identifier: String
    /// Challenge endpoint
    public let challengeUrl: AppAttestURLConvertible
    /// Signed challenge verification endpoint
    public let attestationUrl: AppAttestURLConvertible

    public init(
        identifier: String,
        challengeUrl: AppAttestURLConvertible,
        attestationUrl: AppAttestURLConvertible
    ) {
        self.identifier = identifier
        self.challengeUrl = challengeUrl
        self.attestationUrl = attestationUrl
    }
}

public protocol AppAttestURLConvertible {
    var url: URL { get }
    var httpMethod: String { get }
    var params: Encodable? { get }
}

public extension AppAttestURLConvertible {
    var params: (any Encodable)? { nil }
    var httpMethod: String { HttpMethod.post.rawValue }
}
