//
//  MockLeapServerTests.swift
//  LeapSwiftTests
//

import Testing
import Foundation
@testable import LeapSwift

@Suite("MockLeapServer")
struct MockLeapServerTests {

    // Fast enough that a handful of ticks costs single-digit milliseconds,
    // so these tests don't spend real wall-clock time waiting on frames.
    private static let fastFrameRate: Double = 1000

    @Test func startEmitsConnectedThenDeviceFoundThenFrames() async {
        let server = MockLeapServer(scenario: .idleRightHand, frameRate: Self.fastFrameRate)
        var iterator = server.events.makeAsyncIterator()

        await server.start()
        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        await server.stop()

        guard case .connected = first else {
            Issue.record("expected .connected first, got \(String(describing: first))")
            return
        }
        guard case .deviceFound = second else {
            Issue.record("expected .deviceFound second, got \(String(describing: second))")
            return
        }
        guard case .trackingFrame = third else {
            Issue.record("expected a tracking frame third, got \(String(describing: third))")
            return
        }
    }

    @Test func injectedFrameIsDeliveredUnchanged() async {
        let server = MockLeapServer(scenario: .noHands, frameRate: Self.fastFrameRate)
        var iterator = server.events.makeAsyncIterator()

        let frame = MockHandFactory.frame(scenario: .pinch, frameId: 999, time: 0.5)
        await server.inject(frame)
        let event = await iterator.next()
        await server.stop()

        guard case .trackingFrame(let delivered) = event else {
            Issue.record("expected a tracking frame, got \(String(describing: event))")
            return
        }
        #expect(delivered.frameId == 999)
        #expect(delivered.rightHand?.pinchStrength == frame.rightHand?.pinchStrength)
    }

    @Test func injectedEventIsDeliveredUnchanged() async {
        let server = MockLeapServer(scenario: .noHands, frameRate: Self.fastFrameRate)
        var iterator = server.events.makeAsyncIterator()

        await server.inject(.deviceLost)
        let event = await iterator.next()
        await server.stop()

        guard case .deviceLost = event else {
            Issue.record("expected .deviceLost, got \(String(describing: event))")
            return
        }
    }

    @Test func playStreamsRecordingFramesInOrder() async {
        let server = MockLeapServer(scenario: .noHands, frameRate: Self.fastFrameRate)
        var iterator = server.events.makeAsyncIterator()
        let recording = MockRecording.generate(scenario: .wave, duration: 0.1, frameRate: 30) // 3 frames

        await server.play(recording, loop: false)
        await server.start()

        // Skip .connected and .deviceFound.
        _ = await iterator.next()
        _ = await iterator.next()

        var seenFrameIds: [Int64] = []
        for _ in 0..<recording.frames.count {
            guard case .trackingFrame(let frame) = await iterator.next() else {
                Issue.record("expected a tracking frame")
                break
            }
            seenFrameIds.append(frame.frameId)
        }
        await server.stop()

        #expect(seenFrameIds == recording.frames.map(\.frameId))
    }

    @Test func stopFinishesTheStream() async {
        let server = MockLeapServer(scenario: .idleRightHand, frameRate: Self.fastFrameRate)
        await server.start()
        await server.stop()

        var count = 0
        for await _ in server.events {
            count += 1
            if count > 10_000 { break } // safety net; should never be reached
        }
        // Reaching here at all means the for-await loop above returned on its
        // own, i.e. the stream finished rather than hanging.
        #expect(count <= 10_000)
    }

    @Test func deviceInfoReturnsPseudoDeviceInformation() async {
        let server = MockLeapServer()
        let info = await server.deviceInfo()
        #expect(!info.serialNumber.isEmpty)
    }
}
