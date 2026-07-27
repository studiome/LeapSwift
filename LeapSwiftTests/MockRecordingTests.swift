//
//  MockRecordingTests.swift
//  LeapSwiftTests
//

import Testing
import Foundation
import simd
@testable import LeapSwift

@Suite("Tracking types Codable round trip")
struct TrackingCodableTests {

    private func makeFrame() -> HandFrame {
        MockHandFactory.frame(scenario: .pinch, frameId: 42, time: 0.777)
    }

    @Test func quaternionRoundTripsThroughJSON() throws {
        let original = Quaternion(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9)
        let bone = Bone(previousJoint: .init(1, 2, 3), nextJoint: .init(4, 5, 6), width: 12, rotation: original)

        let data = try JSONEncoder().encode(bone)
        let decoded = try JSONDecoder().decode(Bone.self, from: data)

        #expect(abs(decoded.rotation.imag.x - original.imag.x) < 0.0001)
        #expect(abs(decoded.rotation.imag.y - original.imag.y) < 0.0001)
        #expect(abs(decoded.rotation.imag.z - original.imag.z) < 0.0001)
        #expect(abs(decoded.rotation.real - original.real) < 0.0001)
    }

    @Test func boneRoundTrips() throws {
        let bone = Bone(previousJoint: .init(1, 2, 3), nextJoint: .init(4, 5, 6), width: 12, rotation: .identity)
        let data = try JSONEncoder().encode(bone)
        let decoded = try JSONDecoder().decode(Bone.self, from: data)
        #expect(decoded == bone)
    }

    @Test func handFrameRoundTrips() throws {
        let frame = makeFrame()
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(HandFrame.self, from: data)

        #expect(decoded.frameId == frame.frameId)
        #expect(decoded.timestamp == frame.timestamp)
        #expect(decoded.frameRate == frame.frameRate)
        #expect(decoded.hands.count == frame.hands.count)

        guard let original = frame.rightHand, let roundTripped = decoded.rightHand else {
            Issue.record("expected a right hand in the pinch scenario")
            return
        }
        #expect(roundTripped.id == original.id)
        #expect(roundTripped.type == original.type)
        #expect(roundTripped.palm.position == original.palm.position)
        #expect(roundTripped.thumb.distal.nextJoint == original.thumb.distal.nextJoint)
        #expect(roundTripped.pinchStrength == original.pinchStrength)
        #expect(roundTripped.isPinching == original.isPinching)
    }

    @Test func emptyHandsFrameRoundTrips() throws {
        let frame = MockHandFactory.frame(scenario: .noHands, frameId: 0, time: 0)
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(HandFrame.self, from: data)
        #expect(decoded.hands.isEmpty)
    }
}

// MARK: - MockRecording Tests

@Suite("MockRecording")
struct MockRecordingTests {

    @Test func generateProducesExpectedFrameCount() {
        let recording = MockRecording.generate(scenario: .wave, duration: 1, frameRate: 30)
        #expect(recording.frames.count == 30)
        #expect(recording.frameRate == 30)
        #expect(recording.name == MockScenario.wave.rawValue)
    }

    @Test func generateMatchesMockHandFactoryFrameByFrame() {
        let recording = MockRecording.generate(scenario: .pinch, duration: 0.5, frameRate: 20)
        for (i, frame) in recording.frames.enumerated() {
            let expected = MockHandFactory.frame(scenario: .pinch, frameId: Int64(i), time: TimeInterval(i) / 20, frameRate: 20)
            #expect(frame.frameId == expected.frameId)
            #expect(frame.hands.count == expected.hands.count)
        }
    }

    @Test func writeThenLoadRoundTrips() throws {
        let original = MockRecording.generate(scenario: .openClose, duration: 0.2, frameRate: 30)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        try original.write(to: url)
        let loaded = try MockRecording.load(contentsOf: url)

        #expect(loaded.name == original.name)
        #expect(loaded.frameRate == original.frameRate)
        #expect(loaded.frames.count == original.frames.count)
        #expect(loaded.frames.last?.frameId == original.frames.last?.frameId)
    }

    @Test func writeProducesUnformattedJSON() throws {
        let recording = MockRecording.generate(scenario: .noHands, duration: 0.1, frameRate: 30)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        try recording.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("\n"))
    }

    @Test func loadThrowsForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        #expect(throws: (any Error).self) {
            try MockRecording.load(contentsOf: url)
        }
    }
}

// MARK: - Bundled MockData Tests

// Verifies the JSON files committed under LeapSwift/MockData/ — one is loaded
// through `Bundle.leapSwiftResources`, so this also exercises the SPM/Xcode
// resource shim in MockBundle.swift, not just the JSON itself.
@Suite("Bundled MockData")
struct BundledMockDataTests {

    @Test("Every scenario's bundled recording loads", arguments: MockScenario.allCases)
    func bundledRecordingLoads(scenario: MockScenario) throws {
        let recording = try MockRecording.bundled(scenario)
        #expect(recording.name == scenario.rawValue)
        #expect(recording.frameRate == 30)
    }

    // Catches the case where MockHandFactory or MockRecording.generate changes
    // but the committed JSON under LeapSwift/MockData/ isn't regenerated to
    // match — the two would silently drift apart otherwise.
    //
    // Compared by size and checksum rather than `Data` equality: on a genuine
    // mismatch, a direct `#expect(bundledData == freshData)` asks the testing
    // library to diff two ~100 KB byte buffers, which is dramatically more
    // expensive than computing the checksums in the first place.
    @Test("Bundled recording matches a fresh generate()", arguments: MockScenario.allCases)
    func bundledRecordingMatchesGenerate(scenario: MockScenario) throws {
        let bundled = try MockRecording.bundled(scenario)
        let fresh = MockRecording.generate(scenario: scenario, duration: 1, frameRate: 30)

        let bundledData = try MockRecording.encoder.encode(bundled)
        let freshData = try MockRecording.encoder.encode(fresh)

        let hint = "MockData/\(scenario.rawValue).json is out of date; regenerate it from MockRecording.generate"
        #expect(bundledData.count == freshData.count, Comment(rawValue: hint))
        #expect(fnv1aHash(bundledData) == fnv1aHash(freshData), Comment(rawValue: hint))
    }
}

// A stable, order-sensitive checksum for detecting drift cheaply. Swift's
// built-in `Hashable`/`hashValue` is seeded randomly per process, so it can't
// be used to compare byte buffers across separate `swift test` invocations.
private func fnv1aHash(_ data: Data) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}
