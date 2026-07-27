//
//  MockLeapServer.swift
//  LeapSwift
//

import Foundation

/// A synthetic hand-tracking source that streams the same ``LeapEvent`` shape
/// as a real Ultraleap connection, without a device or the tracking service.
///
/// Drives ``LeapController``'s mock modes internally, but is also usable
/// standalone — for a preview, a SwiftUI canvas, or a test that wants full
/// control over the event sequence via `inject(_:)`.
public actor MockLeapServer {

    /// An async stream of synthetic events, matching ``LeapController/events``.
    ///
    /// Unicast, like the real controller's stream: subscribe once per
    /// consumer.
    public nonisolated let events: AsyncStream<LeapEvent>
    private let eventContinuation: AsyncStream<LeapEvent>.Continuation

    private var scenario: MockScenario
    private let frameRate: Double

    private var streamingTask: Task<Void, Never>?
    private var nextFrameId: Int64 = 0
    private var elapsed: TimeInterval = 0

    private var recording: MockRecording?
    private var loopRecording = true
    private var playbackIndex = 0

    /// Creates a server. No events are emitted until ``start()`` is called.
    ///
    /// - Parameters:
    ///   - scenario: The procedural scenario to stream once started, unless
    ///     ``play(_:loop:)`` selects a recording instead.
    ///   - frameRate: How many frames per second to emit.
    public init(scenario: MockScenario = .idleRightHand, frameRate: Double = 30) {
        self.scenario = scenario
        self.frameRate = frameRate
        var continuation: AsyncStream<LeapEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    /// Starts streaming: ``LeapEvent/connected``, then ``LeapEvent/deviceFound(_:)``,
    /// then a ``LeapEvent/trackingFrame(_:)`` every `1 / frameRate` seconds
    /// until ``stop()``. Calling this again while already started has no
    /// effect.
    public func start() {
        guard streamingTask == nil else { return }
        eventContinuation.yield(.connected)
        eventContinuation.yield(.deviceFound(nil))

        let interval = Duration.seconds(1.0 / frameRate)
        streamingTask = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                guard let self else { return }
                await self.emitNextFrame()
                try? await clock.sleep(for: interval)
            }
        }
    }

    /// Stops streaming and finishes ``events``, ending any `for await` loop
    /// over it. Safe to call more than once, and even if ``start()`` was
    /// never called.
    public func stop() {
        streamingTask?.cancel()
        streamingTask = nil
        eventContinuation.finish()
    }

    /// Switches the procedural scenario streamed once ``start()`` has been
    /// called. Takes effect on the next frame. Has no effect while a
    /// recording set by ``play(_:loop:)`` is active — call `play` with a
    /// freshly generated recording, or restart the server, to go back to
    /// procedural generation.
    public func setScenario(_ scenario: MockScenario) {
        self.scenario = scenario
    }

    /// Injects a tracking frame directly, bypassing the scenario or recording
    /// currently streaming. Delivered as-is, with no modification.
    public func inject(_ frame: HandFrame) {
        eventContinuation.yield(.trackingFrame(frame))
    }

    /// Injects an arbitrary event directly. Delivered as-is.
    public func inject(_ event: LeapEvent) {
        eventContinuation.yield(event)
    }

    /// Switches from procedural generation to replaying `recording`, starting
    /// from its first frame.
    ///
    /// - Parameters:
    ///   - recording: The frames to stream, in order, once ``start()`` has
    ///     been called (or immediately, if it already has been).
    ///   - loop: If `true` (the default), the recording restarts from the
    ///     beginning after its last frame. If `false`, the last frame repeats
    ///     indefinitely once reached.
    public func play(_ recording: MockRecording, loop: Bool = true) {
        self.recording = recording
        self.loopRecording = loop
        self.playbackIndex = 0
    }

    /// A pseudo device, so code that calls ``LeapController/deviceInfo()``
    /// while mocked gets a plausible, non-`nil` result.
    public func deviceInfo() -> DeviceInfo {
        DeviceInfo(serialNumber: "MOCK-0000001", horizontalFOV: 2.3, verticalFOV: 2.0, range: 600_000, baseline: 40_000)
    }

    // Emits one frame: the next frame of the active recording if `play(_:loop:)`
    // was called, otherwise the next procedurally generated frame for `scenario`.
    private func emitNextFrame() {
        if let recording, !recording.frames.isEmpty {
            eventContinuation.yield(.trackingFrame(recording.frames[playbackIndex]))
            playbackIndex += 1
            if playbackIndex >= recording.frames.count {
                playbackIndex = loopRecording ? 0 : recording.frames.count - 1
            }
        } else {
            let frame = MockHandFactory.frame(scenario: scenario, frameId: nextFrameId, time: elapsed, frameRate: Float(frameRate))
            eventContinuation.yield(.trackingFrame(frame))
            nextFrameId += 1
            elapsed += 1.0 / frameRate
        }
    }
}
