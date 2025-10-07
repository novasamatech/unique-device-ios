import Foundation

enum DeviceCheckResult {
    case supported(Data)
    case unsupported
}

extension DeviceCheckResult: HttpRequestModifier {
    func visit(request: inout URLRequest) throws {
        switch self {
        case let .supported(data):
            let token = data.base64EncodedString()
            request.setValue(token, forHTTPHeaderField: "Device-Token-iOS")
        case .unsupported:
            break
        }
    }
}
