import Foundation
import LeapC

/// Errors thrown by the LeapSwift framework.
public enum LeapError: Error, LocalizedError, Sendable {
    case connectionFailed(Int32)
    case deviceNotFound
    case openDeviceFailed(Int32)
    case policyError(Int32)
    case trackingUnavailable

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let code):
            return "Failed to connect to Ultraleap service (code: 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .deviceNotFound:
            return "No Ultraleap device found"
        case .openDeviceFailed(let code):
            return "Failed to open device (code: 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .policyError(let code):
            return "Policy error (code: 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .trackingUnavailable:
            return "Hand tracking is unavailable"
        }
    }

    init(_ rs: eLeapRS) {
        self = .connectionFailed(Int32(rs.rawValue))
    }
}
