import Foundation
import Operation_iOS

public protocol AppAttestRepositoryFactoryProtocol {
    func createAppAttestRepository() -> AnyDataProviderRepository<AppAttestLocalSettings>
}

public final class AppAttestProviderFactory {
    let repositoryFactory: AppAttestRepositoryFactoryProtocol
    let operationQueue: OperationQueue

    public init(
        repositoryFactory: AppAttestRepositoryFactoryProtocol,
        operationQueue: OperationQueue,
    ) {
        self.repositoryFactory = repositoryFactory
        self.operationQueue = operationQueue
    }

    public func createProvider(
        with configuration: AppAttestConfiguration
    ) -> AppAttestProviding {
        let repository = repositoryFactory.createAppAttestRepository()

        let attestationRequestFactory = AppAttestFactory(
            challengeUrl: configuration.challengeUrl,
            attestationUrl: configuration.attestationUrl
        )

        let authProvider = AttestProvider(
            attestationIdentifier: configuration.identifier,
            appAttestService: AppAttestService(),
            attestFactory: attestationRequestFactory,
            repository: repository,
            operationQueue: operationQueue
        )

        authProvider.setup()

        return authProvider
    }
}
