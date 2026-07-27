//
//  MockPolicyTests.swift
//  LeapSwiftTests
//

import Testing
@testable import LeapSwift

// MARK: - MockPolicy Resolution Tests

@Suite("MockPolicy resolution")
struct MockPolicyResolutionTests {

    @Test func defaultsToDisabledWhenNothingSet() {
        let policy = MockPolicy.resolved(environment: [:], arguments: ["app"])
        #expect(policy == .disabled)
    }

    @Test func customFallbackIsUsedWhenNothingSet() {
        let policy = MockPolicy.resolved(environment: [:], arguments: ["app"], default: .always)
        #expect(policy == .always)
    }

    @Test("Environment values map to policies", arguments: [
        ("off", MockPolicy.disabled),
        ("disabled", .disabled),
        ("0", .disabled),
        ("auto", .whenNoDevice),
        ("whenNoDevice", .whenNoDevice),
        ("always", .always),
        ("on", .always),
        ("1", .always)
    ])
    func environmentValueMapsToPolicy(raw: String, expected: MockPolicy) {
        let policy = MockPolicy.resolved(environment: ["LEAPSWIFT_MOCK": raw], arguments: ["app"])
        #expect(policy == expected)
    }

    @Test func unknownEnvironmentValueFallsBackToDefault() {
        let policy = MockPolicy.resolved(environment: ["LEAPSWIFT_MOCK": "bogus"], arguments: ["app"])
        #expect(policy == .disabled)
    }

    @Test func launchArgumentTakesPrecedenceOverEnvironment() {
        let policy = MockPolicy.resolved(
            environment: ["LEAPSWIFT_MOCK": "disabled"],
            arguments: ["app", "-LeapSwiftMock", "always"]
        )
        #expect(policy == .always)
    }

    @Test func launchArgumentAloneIsHonored() {
        let policy = MockPolicy.resolved(environment: [:], arguments: ["app", "-LeapSwiftMock", "whenNoDevice"])
        #expect(policy == .whenNoDevice)
    }

    @Test func unknownLaunchArgumentFallsBackToDefault() {
        let policy = MockPolicy.resolved(environment: [:], arguments: ["app", "-LeapSwiftMock", "bogus"])
        #expect(policy == .disabled)
    }

    @Test func trailingFlagWithNoValueIsIgnored() {
        let policy = MockPolicy.resolved(environment: ["LEAPSWIFT_MOCK": "always"], arguments: ["app", "-LeapSwiftMock"])
        #expect(policy == .always)
    }
}

// MARK: - MockActivation Tests

@Suite("MockActivation")
struct MockActivationTests {

    @Test func startsImmediatelyOnlyForAlways() {
        #expect(MockActivation.shouldStartImmediately(policy: .always))
        #expect(!MockActivation.shouldStartImmediately(policy: .whenNoDevice))
        #expect(!MockActivation.shouldStartImmediately(policy: .disabled))
    }

    @Test func fallsBackOnConnectionFailureOnlyForWhenNoDevice() {
        #expect(MockActivation.shouldFallBackOnConnectionFailure(policy: .whenNoDevice))
        #expect(!MockActivation.shouldFallBackOnConnectionFailure(policy: .always))
        #expect(!MockActivation.shouldFallBackOnConnectionFailure(policy: .disabled))
    }

    @Test func fallsBackToMockOnDeviceNotFoundWhenNoDevice() {
        #expect(MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .error(.deviceNotFound)))
    }

    @Test func fallsBackToMockOnOpenDeviceFailedWhenNoDevice() {
        #expect(MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .error(.openDeviceFailed(0))))
    }

    @Test func fallsBackToMockOnDisconnectedWhenNoDevice() {
        #expect(MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .disconnected))
    }

    @Test func doesNotFallBackToMockForOtherPolicies() {
        #expect(!MockActivation.shouldFallBackToMock(policy: .disabled, event: .disconnected))
        #expect(!MockActivation.shouldFallBackToMock(policy: .always, event: .disconnected))
    }

    @Test func doesNotFallBackToMockForUnrelatedEvents() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .connected))
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .deviceFound(nil)))
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .deviceLost))
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .trackingFrame(frame)))
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .error(.connectionFailed(0))))
        #expect(!MockActivation.shouldFallBackToMock(policy: .whenNoDevice, event: .error(.policyError(0))))
    }

    @Test func stopsMockOnlyOnRealTrackingFrame() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(MockActivation.shouldStopMock(event: .trackingFrame(frame)))
        #expect(!MockActivation.shouldStopMock(event: .connected))
        #expect(!MockActivation.shouldStopMock(event: .deviceFound(nil)))
        #expect(!MockActivation.shouldStopMock(event: .disconnected))
        #expect(!MockActivation.shouldStopMock(event: .deviceLost))
        #expect(!MockActivation.shouldStopMock(event: .error(.deviceNotFound)))
    }
}
