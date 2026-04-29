import Foundation

protocol AppAttestClientHashing {
    func hash(challenge: Data, clientId: Data?, data: Data?) throws -> Data
}

final class AppAttestClientHashCalculator: AppAttestClientHashing {
    func hash(challenge: Data, clientId: Data?, data: Data?) throws -> Data {
        guard let data else {
            return challenge.sha256()
        }
        
        let dataHash = data.sha256()
        
        guard let clientId else {
            return (challenge + dataHash).sha256()
        }
        
        return (challenge + clientId + dataHash).sha256()
    }
}
