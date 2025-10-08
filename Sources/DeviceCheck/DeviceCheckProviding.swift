import DeviceCheck
import Operation_iOS

public protocol DeviceCheckProviding {
    func deviceTokenModifier() -> CompoundOperationWrapper<HttpRequestModifier>
}

public final class DeviceCheckProvider {
    let device: DCDevice = .current
    public init() {}
}

extension DeviceCheckProvider: DeviceCheckProviding {
    public func deviceTokenModifier() -> CompoundOperationWrapper<any HttpRequestModifier> {
        let operation = AsyncClosureOperation<HttpRequestModifier> { [device] completion in
            guard device.isSupported else {
                completion(.success(DeviceCheckResult.unsupported))
                return
            }

            device.generateToken { data, error in
                guard error == nil else {
                    completion(.failure(error!))
                    return
                }

                guard let data else {
                    completion(.failure(HttpRequestModifierError.invalidData))
                    return
                }

                completion(.success(DeviceCheckResult.supported(data)))
            }
        }

        return CompoundOperationWrapper(targetOperation: operation)
    }
}
