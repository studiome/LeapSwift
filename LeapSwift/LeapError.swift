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
        // eLeapRS values such as eLeapRS_NotConnected (0xE2010005) exceed
        // Int32.max, so Int32(_:) would trap on overflow. bitPattern:
        // preserves the raw bits, which is all callers need — they only
        // ever re-render the code in hex via errorDescription.
        self = .connectionFailed(Int32(bitPattern: rs.rawValue))
    }
}
