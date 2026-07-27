//
//  MockScenario.swift
//  LeapSwift
//

/// A named, procedurally generated hand-tracking scenario used by
/// ``MockHandFactory``, ``MockLeapServer``, and ``MockRecording``.
///
/// Every scenario is periodic, so looping its recording produces a seamless,
/// indefinitely long clip.
public enum MockScenario: String, CaseIterable, Sendable {
    /// No hands in view.
    case noHands
    /// A single relaxed right hand, gently swaying.
    case idleRightHand
    /// Both hands, relaxed and idle.
    case bothHandsIdle
    /// A right hand cycling between an open palm and a closed fist.
    case openClose
    /// A right hand cycling through a thumb-to-index pinch.
    case pinch
    /// A right hand waving side to side.
    case wave
}
