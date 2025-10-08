import Foundation

protocol AppAttestClientHashing {
    func hash(challenge: Data, data: Data?) throws -> Data
}

final class AppAttestClientHashCalculator: AppAttestClientHashing {
    func hash(challenge: Data, data: Data?) throws -> Data {
        guard let data else {
            return challenge.sha256()
        }

        return (challenge + data.sha256()).sha256()
    }
}
