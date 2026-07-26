import Foundation
import LeapC

/// Errors thrown by the LeapSwift framework.
///
/// The associated `Int32` values are raw `eLeapRS` result codes from the
/// underlying LeapC library, rendered in hexadecimal by `errorDescription`.
public enum LeapError: Error, LocalizedError, Sendable {
    /// The connection to the Ultraleap service could not be created, opened, or
    /// used. Most often the service is not running.
    case connectionFailed(Int32)
    /// No Ultraleap device is attached.
    case deviceNotFound
    /// A device was found but could not be opened for tracking.
    case openDeviceFailed(Int32)
    /// A policy flag change, such as background frames, was rejected.
    case policyError(Int32)

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
        }
    }

    init(_ rs: eLeapRS) {
        self = .connectionFailed(Int32(rs.rawValue))
    }
}
