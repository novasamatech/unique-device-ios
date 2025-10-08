import Foundation
import Operation_iOS

struct AppAttestChallengeResponse: Decodable {
    @Base64Codable var challenge: Data
}

struct AttestationData: Codable {
    let keyId: String
    @Base64Codable var challenge: Data
    @Base64Codable var attestation: Data
}

// MARK: -

protocol AppAttestFactoryProtocol {
    func createGetChallengeWrapper() -> CompoundOperationWrapper<AppAttestChallengeResponse>

    func createAttestationWrapper(
        _ dataClosure: @escaping () throws -> AttestationData
    ) -> CompoundOperationWrapper<Void>
}

final class AppAttestFactory {
    let challengeUrl: AppAttestURLConvertible
    let attestationUrl: AppAttestURLConvertible

    init(
        challengeUrl: AppAttestURLConvertible,
        attestationUrl: AppAttestURLConvertible
    ) {
        self.challengeUrl = challengeUrl
        self.attestationUrl = attestationUrl
    }

    private func createGenericRequestWrapper<R: NetworkResultFactoryProtocol>(
        for endpoint: AppAttestURLConvertible,
        bodyParamsClosure: @escaping () throws -> Encodable?,
        responseFactory: R
    ) -> NetworkOperation<R.ResultType> {
        let requestFactory = BlockNetworkRequestFactory {
            var request = URLRequest(url: endpoint.url)
            request.httpMethod = endpoint.httpMethod
            request.setValue(
                HttpContentType.json.rawValue,
                forHTTPHeaderField: HttpHeaderKey.contentType.rawValue
            )

            let bodyParams = try bodyParamsClosure()
            if let bodyParams {
                request.httpBody = try JSONEncoder().encode(bodyParams)
            }

            return request
        }

        return NetworkOperation(
            requestFactory: requestFactory,
            resultFactory: AnyNetworkResultFactory(factory: responseFactory)
        )
    }
}

extension AppAttestFactory: AppAttestFactoryProtocol {
    func createGetChallengeWrapper() -> CompoundOperationWrapper<AppAttestChallengeResponse> {
        let responseFactory = AnyNetworkResultFactory<AppAttestChallengeResponse>(processingBlock: {
            try JSONDecoder().decode(AppAttestChallengeResponse.self, from: $0)
        })

        let requestOperation = createGenericRequestWrapper(
            for: challengeUrl,
            bodyParamsClosure: { nil },
            responseFactory: responseFactory
        )

        return CompoundOperationWrapper(targetOperation: requestOperation)
    }

    func createAttestationWrapper(
        _ dataClosure: @escaping () throws -> AttestationData
    ) -> CompoundOperationWrapper<Void> {
        let responseFactory = AnyNetworkResultFactory<Void> { () }

        let requestOperation = createGenericRequestWrapper(
            for: attestationUrl,
            bodyParamsClosure: { try dataClosure() },
            responseFactory: responseFactory
        )

        return CompoundOperationWrapper(targetOperation: requestOperation)
    }
}
