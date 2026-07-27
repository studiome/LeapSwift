//
//  LeapControllerMockTests.swift
//  LeapSwiftTests
//

import Testing
@testable import LeapSwift

@Suite("LeapController mock integration")
struct LeapControllerMockTests {

    @Test func mockAlwaysStreamsConnectedAndFramesWithoutADevice() async throws {
        let controller = try await LeapController(mock: .always, mockScenario: .idleRightHand)
        var iterator = controller.events.makeAsyncIterator()

        let first = await iterator.next()
        guard case .connected = first else {
            Issue.record("expected .connected first, got \(String(describing: first))")
            await controller.stop()
            return
        }

        // Keep pulling until a tracking frame shows up (deviceFound may come first).
        var sawFrame = false
        for _ in 0..<10 {
            guard case .trackingFrame = await iterator.next() else { continue }
            sawFrame = true
            break
        }
        #expect(sawFrame)

        await controller.stop()
    }

    @Test func mockAlwaysNeverTouchesRealDeviceAPIs() async throws {
        let controller = try await LeapController(mock: .always)

        // None of these hit LeapC while mocked — all must succeed rather than
        // throw `.connectionFailed`, which is what they'd do with `_connection == nil`
        // outside mock mode.
        let info = await controller.deviceInfo()
        #expect(info != nil)

        await #expect(throws: Never.self) {
            try await controller.setTrackingMode(.headMounted)
        }
        await #expect(throws: Never.self) {
            try await controller.setBackgroundFrames(enabled: true)
        }
        let version = try await controller.version(of: .serverLibrary)
        #expect(version.major >= 0)

        await controller.stop()
    }

    @Test func mockDisabledConstructsAndStopsLikeBefore() async throws {
        // `.disabled` must behave exactly like the pre-mock initializer: it
        // talks to real LeapC, so this only asserts it doesn't throw or hang —
        // asserting anything about an actual device would depend on this
        // machine's hardware.
        let controller = try await LeapController(mock: .disabled)
        await controller.stop()
    }
}
