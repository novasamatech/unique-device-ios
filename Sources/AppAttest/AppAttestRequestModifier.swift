import Foundation

public enum HttpRequestModifierError: Error {
    case invalidData
}

public protocol HttpRequestModifier {
    func visit(request: inout URLRequest) throws
}

extension AppAttestAssertionModelResult: HttpRequestModifier {
    func visit(request: inout URLRequest) throws {
        switch self {
        case let .supported(model):
            request.httpBody = model.bodyData

            request.setValue(model.bundleId, forHTTPHeaderField: "Auth-iOS-Package")
            request.setValue(model.assertion.base64EncodedString(), forHTTPHeaderField: "Auth-Payload")
            request.setValue(model.challenge.base64EncodedString(), forHTTPHeaderField: "Auth-Challenge")
            request.setValue(model.keyId, forHTTPHeaderField: "Auth-iOS-KeyId")

        case let .unsupported(bodyData):
            #if targetEnvironment(simulator) && DEBUG
                request.httpBody = bodyData
            #else
                throw HttpRequestModifierError.invalidData
            #endif
        }
    }
}
