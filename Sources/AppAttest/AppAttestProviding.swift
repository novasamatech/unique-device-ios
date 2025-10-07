import Foundation
import DeviceCheck
import Operation_iOS

public protocol AppAttestProviding {
    func setup()
    func appAttestModifier(
        for bodyDataClosure: @escaping () throws -> Data?
    ) -> CompoundOperationWrapper<HttpRequestModifier>
}

public final class AttestProvider {
    struct PendingRequest {
        let resultClosure: (Result<HttpRequestModifier, Error>) -> Void
        let bodyData: Data?
        let queue: DispatchQueue
    }

    let attestationIdentifier: String
    let appAttestService: AppAttestServiceProtocol
    let attestFactory: AppAttestFactoryProtocol
    let repository: AnyDataProviderRepository<AppAttestLocalSettings>
    let operationQueue: OperationQueue
    let syncQueue: DispatchQueue
    let logger: LoggerProtocol?

    private var attestedKeyId: AppAttestKeyId?
    private let attestationCancellable = CancellableCallStore()
    private var pendingRequests: [UUID: PendingRequest] = [:]
    private var pendingAssertions: [UUID: CancellableCallStore] = [:]

    init(
        attestationIdentifier: String,
        appAttestService: AppAttestServiceProtocol,
        attestFactory: AppAttestFactoryProtocol,
        repository: AnyDataProviderRepository<AppAttestLocalSettings>,
        operationQueue: OperationQueue,
        logger: LoggerProtocol? = nil
    ) {
        self.attestationIdentifier = attestationIdentifier
        self.appAttestService = appAttestService
        self.attestFactory = attestFactory
        self.repository = repository
        self.operationQueue = operationQueue
        self.logger = logger

        syncQueue = DispatchQueue(label: "io.appattest.\(UUID().uuidString)")
    }
}

extension AttestProvider {
    private func loadLocalSettingsWrapper() -> CompoundOperationWrapper<AppAttestLocalSettings?> {
        let fetchOperation = repository.fetchOperation(
            by: { [attestationIdentifier] in attestationIdentifier },
            options: .init()
        )

        return CompoundOperationWrapper(targetOperation: fetchOperation)
    }

    private func saveLocalSettingsWrapper(
        _ settingsClosure: @escaping () throws -> AppAttestLocalSettings
    ) -> CompoundOperationWrapper<Void> {
        let saveOperation = repository.saveOperation({
            let settings = try settingsClosure()
            return [settings]
        }, {
            []
        })

        return CompoundOperationWrapper(targetOperation: saveOperation)
    }

    private func createAttestationWrapper(for keyId: AppAttestKeyId?) -> CompoundOperationWrapper<AppAttestKeyId> {
        let challengeWrapper = attestFactory.createGetChallengeWrapper()
        let attestationWrapper = appAttestService.createAttestationWrapper(
            for: {
                try challengeWrapper.targetOperation.extractNoCancellableResultData().challenge
            },
            using: keyId
        )

        attestationWrapper.addDependency(wrapper: challengeWrapper)

        let attestationInitSaveWrapper = saveLocalSettingsWrapper { [attestationIdentifier] in
            let appAttestModel = try attestationWrapper.targetOperation.extractNoCancellableResultData()
            return AppAttestLocalSettings(
                persistentId: attestationIdentifier,
                keyId: appAttestModel.keyId,
                isAttested: false
            )
        }

        attestationInitSaveWrapper.addDependency(wrapper: attestationWrapper)

        let remoteAttestationWrapper = attestFactory.createAttestationWrapper {
            try attestationInitSaveWrapper.targetOperation.extractNoCancellableResultData()

            let attestationModel = try attestationWrapper.targetOperation.extractNoCancellableResultData()

            return AttestationData(
                keyId: attestationModel.keyId,
                challenge: attestationModel.challenge,
                attestation: attestationModel.result
            )
        }

        remoteAttestationWrapper.addDependency(wrapper: attestationInitSaveWrapper)

        let attestationSaveIfSuccessWrapper = saveLocalSettingsWrapper { [attestationIdentifier] in
            _ = try remoteAttestationWrapper.targetOperation.extractNoCancellableResultData()

            let attestationModel = try attestationWrapper.targetOperation.extractNoCancellableResultData()

            return
                AppAttestLocalSettings(
                    persistentId: attestationIdentifier,
                    keyId: attestationModel.keyId,
                    isAttested: true
                )
        }

        attestationSaveIfSuccessWrapper.addDependency(wrapper: remoteAttestationWrapper)

        let resultOperation = ClosureOperation<AppAttestKeyId> {
            _ = try attestationSaveIfSuccessWrapper.targetOperation.extractNoCancellableResultData()
            let attestationModel = try attestationWrapper.targetOperation.extractNoCancellableResultData()

            return attestationModel.keyId
        }

        resultOperation.addDependency(attestationSaveIfSuccessWrapper.targetOperation)

        let preSaveDep = challengeWrapper.allOperations + attestationWrapper.allOperations +
            attestationInitSaveWrapper.allOperations
        let remoteDep = remoteAttestationWrapper.allOperations + attestationSaveIfSuccessWrapper.allOperations

        return CompoundOperationWrapper(targetOperation: resultOperation, dependencies: preSaveDep + remoteDep)
    }

    private func loadAttestationIfNeeded() {
        guard !attestationCancellable.hasCall, attestedKeyId == nil else {
            return
        }

        guard appAttestService.isSupported else {
            return
        }

        let settingsWrapper = loadLocalSettingsWrapper()

        let attestationWrapper = OperationCombiningService<AppAttestKeyId>.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) {
            let settings = try settingsWrapper.targetOperation.extractNoCancellableResultData()
            let isAttested = settings?.isAttested ?? false

            guard let settings, isAttested else {
                return self.createAttestationWrapper(for: settings?.keyId)
            }

            return CompoundOperationWrapper.createWithResult(settings.keyId)
        }

        attestationWrapper.addDependency(wrapper: settingsWrapper)

        let totalWrapper = attestationWrapper.insertingHead(operations: settingsWrapper.allOperations)

        executeCancellable(
            wrapper: totalWrapper,
            inOperationQueue: operationQueue,
            backingCallIn: attestationCancellable,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case let .success(keyId):
                self?.logger?.debug("Attestation succeeded")
                self?.attestedKeyId = keyId
                self?.handleResolved(keyId: keyId)
            case let .failure(error):
                self?.logger?.debug("Attestation failed: \(error)")
                self?.handleAttestation(error: error)
            }
        }
    }

    private func handleResolved(keyId: AppAttestKeyId) {
        let allRequests = pendingRequests
        pendingRequests = [:]

        allRequests.forEach { requestId, request in
            fetchAssertion(
                for: requestId,
                bodyData: request.bodyData,
                keyId: keyId,
                runningCompletionIn: request.queue,
                completion: request.resultClosure
            )
        }
    }

    private func checkErrorAndDiscardKeyIfNeeded(_ error: Error) {
        guard
            let serviceError = error as? AppAttestServiceError,
            case .invalidKeyId = serviceError
        else {
            return
        }

        let removeOperation = repository.saveOperation(
            { [] },
            { [attestationIdentifier] in [attestationIdentifier] }
        )

        execute(
            operation: removeOperation,
            inOperationQueue: operationQueue,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case .success:
                self?.attestedKeyId = nil
            case .failure:
                break
            }
        }
    }

    private func handleAttestation(error: Error) {
        checkErrorAndDiscardKeyIfNeeded(error)

        let allRequests = pendingRequests.values
        pendingRequests = [:]

        allRequests.forEach { request in
            request.queue.async {
                request.resultClosure(.failure(error))
            }
        }
    }

    private func doAssertion(
        for requestId: UUID,
        bodyData: Data?,
        queue: DispatchQueue,
        completion: @escaping (Result<HttpRequestModifier, Error>) -> Void
    ) {
        guard appAttestService.isSupported else {
            queue.async {
                completion(.success(AppAttestAssertionModelResult.unsupported(bodyData: bodyData)))
            }

            return
        }

        if let attestedKeyId {
            fetchAssertion(
                for: requestId,
                bodyData: bodyData,
                keyId: attestedKeyId,
                runningCompletionIn: queue,
                completion: completion
            )
        } else {
            pendingRequests[requestId] = .init(
                resultClosure: completion,
                bodyData: bodyData,
                queue: queue
            )

            loadAttestationIfNeeded()
        }
    }

    private func cancelAssertion(for requestId: UUID) {
        pendingRequests[requestId] = nil
        pendingAssertions[requestId]?.cancel()
        pendingAssertions[requestId] = nil
    }

    private func fetchAssertion(
        for requestId: UUID,
        bodyData: Data?,
        keyId: AppAttestKeyId,
        runningCompletionIn queue: DispatchQueue,
        completion: @escaping (Result<HttpRequestModifier, Error>) -> Void
    ) {
        let callStore = CancellableCallStore()
        pendingAssertions[requestId] = callStore

        let challengeWrapper = attestFactory.createGetChallengeWrapper()
        let assertionWrapper = appAttestService.createAssertionWrapper(
            challengeClosure: { try challengeWrapper.targetOperation.extractNoCancellableResultData().challenge },
            dataClosure: { bodyData },
            keyId: keyId
        )

        assertionWrapper.addDependency(wrapper: challengeWrapper)

        let totalWrapper = assertionWrapper.insertingHead(operations: challengeWrapper.allOperations)
        logger?.debug("Will start assertion: \(requestId)")

        executeCancellable(
            wrapper: totalWrapper,
            inOperationQueue: operationQueue,
            backingCallIn: callStore,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            self?.pendingAssertions[requestId] = nil

            switch result {
            case let .success(model):
                self?.logger?.debug("Assertion succeeded: \(requestId)")
                queue.async {
                    completion(.success(AppAttestAssertionModelResult.supported(model)))
                }
            case let .failure(error):
                self?.logger?.debug("Assertion failed: \(error)")
                self?.checkErrorAndDiscardKeyIfNeeded(error)

                queue.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

extension AttestProvider: AppAttestProviding {
    public func setup() {
        syncQueue.async {
            self.loadAttestationIfNeeded()
        }
    }

    public func appAttestModifier(
        for bodyDataClosure: @escaping () throws -> Data?
    ) -> CompoundOperationWrapper<HttpRequestModifier> {
        let requestId = UUID()

        let operation = AsyncClosureOperation<HttpRequestModifier>(
            operationClosure: { [weak self] completion in
                let bodyData = try bodyDataClosure()

                self?.syncQueue.async {
                    self?.doAssertion(
                        for: requestId,
                        bodyData: bodyData,
                        queue: .global(),
                        completion: completion
                    )
                }

            },
            cancelationClosure: { [weak self] in
                self?.syncQueue.async {
                    self?.cancelAssertion(for: requestId)
                }
            }
        )

        return CompoundOperationWrapper(targetOperation: operation)
    }
}
