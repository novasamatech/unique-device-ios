import Foundation

protocol AppAttestClientHashing {
    func hash(challenge: Data, clientId: Data?, data: Data?) throws -> Data
}

final class AppAttestClientHashCalculator: AppAttestClientHashing {
    func hash(challenge: Data, clientId: Data?, data: Data?) throws -> Data {
        let payload = switch (clientId, data) {
        case (.none, .none):
            challenge.sha256()
        case let (.some(clientId), .none):
            challenge + clientId.sha256()
        case let (.none, .some(data)):
            challenge + data.sha256()
        case let (.some(clientId), .some(data)):
            challenge + clientId + data.sha256()
        }
        
        return payload.sha256()
    }
}
