//
//  MockPolicy.swift
//  LeapSwift
//

import Foundation

// MARK: - Mock Policy

/// Controls whether ``LeapController`` uses synthetic hand data instead of a
/// real Ultraleap device.
///
/// The default is ``disabled``: nothing about a normal `LeapController()` call
/// changes unless a policy is chosen explicitly, so a release build can never
/// silently stream fake frames.
public enum MockPolicy: Equatable, Sendable {
    /// Never mock. LeapC only — identical to the framework's behavior before
    /// mocking existed. The default.
    case disabled
    /// Try the real device first; fall back to the mock if the connection
    /// cannot be made or no device is found, and switch back if a real device
    /// later starts producing frames.
    case whenNoDevice
    /// Mock only. `LeapC` is never touched.
    case always

    /// Resolves a policy from the environment and launch arguments, without
    /// touching global state — a pure function so the precedence rules are
    /// directly testable.
    ///
    /// The launch argument takes precedence over the environment variable
    /// because it can be set per Xcode scheme, which is more convenient to
    /// toggle for a single run than an environment variable.
    ///
    /// - Parameters:
    ///   - environment: The environment to read `LEAPSWIFT_MOCK` from.
    ///     Defaults to the process environment.
    ///   - arguments: The launch arguments to look for `-LeapSwiftMock` in.
    ///     Defaults to `CommandLine.arguments`.
    ///   - fallback: The policy to use when neither source specifies a
    ///     recognized value. Defaults to ``disabled``.
    /// - Returns: The resolved policy.
    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        default fallback: MockPolicy = .disabled
    ) -> MockPolicy {
        if let raw = value(forFlag: "-LeapSwiftMock", in: arguments), let policy = parse(raw) {
            return policy
        }
        if let raw = environment["LEAPSWIFT_MOCK"], let policy = parse(raw) {
            return policy
        }
        return fallback
    }

    // Returns the value following `flag` in `arguments`, if present.
    private static func value(forFlag flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag), flagIndex + 1 < arguments.count else {
            return nil
        }
        return arguments[flagIndex + 1]
    }

    private static func parse(_ raw: String) -> MockPolicy? {
        switch raw.lowercased() {
        case "off", "disabled", "0":       return .disabled
        case "auto", "whennodevice":       return .whenNoDevice
        case "always", "on", "1":          return .always
        default:                           return nil
        }
    }
}

// MARK: - Mock Activation

// Pure decision functions for switching between the real device and the mock.
// Kept separate from ``LeapController`` so the branching logic is testable
// without a connection, mirroring `LeapController.shouldOpenDevice(for:)`.
enum MockActivation {

    // Whether the mock should be started as soon as the controller is created,
    // without attempting a real connection at all.
    static func shouldStartImmediately(policy: MockPolicy) -> Bool {
        policy == .always
    }

    // Whether a failed real connection attempt should fall back to the mock
    // instead of throwing.
    static func shouldFallBackOnConnectionFailure(policy: MockPolicy) -> Bool {
        policy == .whenNoDevice
    }

    // Whether an event from the real connection means no device is available,
    // and so the mock should take over.
    static func shouldFallBackToMock(policy: MockPolicy, event: LeapEvent) -> Bool {
        guard policy == .whenNoDevice else { return false }
        switch event {
        case .error(.deviceNotFound), .error(.openDeviceFailed), .disconnected:
            return true
        default:
            return false
        }
    }

    // Whether a real tracking frame means the mock should stop and hand
    // control back to the real device.
    static func shouldStopMock(event: LeapEvent) -> Bool {
        if case .trackingFrame = event { return true }
        return false
    }
}
