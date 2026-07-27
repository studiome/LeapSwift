//
//  MockHandFactory.swift
//  LeapSwift
//

import Foundation
import simd

// MARK: - Mock Hand Pose

/// A synthetic hand placement and finger curl at one instant.
///
/// `MockHandPose` has no notion of time — it is the input to
/// ``MockHandFactory/hand(type:id:pose:)``, which builds a full skeleton from
/// it. Time-derived fields such as ``Palm/velocity`` and ``Hand/visibleTime``
/// are filled in separately by ``MockHandFactory/frame(scenario:frameId:time:frameRate:)``,
/// which does have a timeline to differentiate against.
public struct MockHandPose: Equatable, Sendable {
    /// Center of the palm, in millimeters from the device origin.
    public var position: Vector3
    /// Orientation of the whole hand.
    public var orientation: Quaternion
    /// Curl of the index, middle, ring, and pinky fingers in that order,
    /// `0` (straight) to `1` (fully curled into the palm).
    public var curl: SIMD4<Float>
    /// Curl of the thumb, `0` (straight) to `1` (fully curled).
    public var thumbCurl: Float

    /// Creates a pose.
    public init(position: Vector3, orientation: Quaternion, curl: SIMD4<Float>, thumbCurl: Float) {
        self.position = position
        self.orientation = orientation
        self.curl = curl
        self.thumbCurl = thumbCurl
    }
}

// MARK: - Mock Hand Factory

/// Builds deterministic, procedurally generated ``Hand`` and ``HandFrame``
/// values, with no device, service, or file access.
///
/// Every function here is a pure function of its arguments — no clock, no
/// randomness, no shared mutable state — so the same inputs always produce the
/// same output. That determinism is what lets
/// ``MockRecording/generate(scenario:duration:frameRate:)`` serialize a
/// scenario once and have it match forever after.
public enum MockHandFactory {

    /// Builds a full tracking frame for `scenario` at `time`.
    ///
    /// - Parameters:
    ///   - scenario: Which canned scenario to animate.
    ///   - frameId: The frame identifier to stamp on the result.
    ///   - time: Seconds since the scenario began. Drives every animated value.
    ///   - frameRate: The frame rate to report, and the step used to compute
    ///     ``Palm/velocity`` by finite difference against `time - 1/frameRate`.
    /// - Returns: A frame with zero, one, or two hands depending on `scenario`.
    public static func frame(
        scenario: MockScenario,
        frameId: Int64,
        time: TimeInterval,
        frameRate: Float = 30
    ) -> HandFrame {
        let dt = 1.0 / Double(frameRate)
        let hands: [Hand] = [HandType.left, .right].compactMap { type in
            guard let currentPose = pose(scenario: scenario, handType: type, time: time) else { return nil }

            let velocity: Vector3
            if let previousPose = pose(scenario: scenario, handType: type, time: time - dt) {
                velocity = (currentPose.position - previousPose.position) / Float(dt)
            } else {
                velocity = .zero
            }
            let visibleTime = UInt64(max(0, time) * 1_000_000)

            let base = hand(type: type, id: defaultId(for: type), pose: currentPose)
            return withRuntimeState(base, velocity: velocity, visibleTime: visibleTime)
        }
        return HandFrame(frameId: frameId, timestamp: Int64((time * 1_000_000).rounded()), hands: hands, frameRate: frameRate)
    }

    /// Builds a single hand from a pose, with no time context.
    ///
    /// ``Hand/visibleTime`` and ``Palm/velocity`` are `0` here, since neither
    /// can be derived from a single instantaneous pose. Use ``frame(scenario:frameId:time:frameRate:)``
    /// when those need real values.
    ///
    /// - Parameters:
    ///   - type: Left or right hand. Left is the exact X-axis mirror of right.
    ///   - id: The hand identifier to stamp on the result.
    ///   - pose: The placement and finger curl to build from.
    /// - Returns: A fully populated hand.
    public static func hand(type: HandType, id: UInt32, pose: MockHandPose) -> Hand {
        let thumb  = finger(spec: thumbSpec,  curl: pose.thumbCurl, pose: pose, fingerId: 0, mirror: type == .left)
        let index  = finger(spec: indexSpec,  curl: pose.curl.x,    pose: pose, fingerId: 1, mirror: type == .left)
        let middle = finger(spec: middleSpec, curl: pose.curl.y,    pose: pose, fingerId: 2, mirror: type == .left)
        let ring   = finger(spec: ringSpec,   curl: pose.curl.z,    pose: pose, fingerId: 3, mirror: type == .left)
        let pinky  = finger(spec: pinkySpec,  curl: pose.curl.w,    pose: pose, fingerId: 4, mirror: type == .left)

        let pinchDistance = simd_distance(thumb.tipPosition, index.tipPosition)
        let grabStrength = (pose.curl.x + pose.curl.y + pose.curl.z + pose.curl.w) / 4
        let pinchStrength = unitClamp((pinchOpenDistance - pinchDistance) / (pinchOpenDistance - pinchClosedDistance))

        return Hand(
            id: id,
            type: type,
            confidence: 1,
            visibleTime: 0,
            pinchDistance: pinchDistance,
            grabAngle: grabStrength * maxGrabAngle,
            pinchStrength: pinchStrength,
            grabStrength: grabStrength,
            palm: palm(pose: pose),
            thumb: thumb,
            index: index,
            middle: middle,
            ring: ring,
            pinky: pinky,
            arm: arm(pose: pose),
            isPinching: pinchStrength > 0.8
        )
    }

    // MARK: Per-Scenario Animation

    // Returns the pose for `handType` in `scenario` at `time`, or `nil` if
    // that hand is not present in the scenario. Presence never changes within
    // a scenario, so callers can safely evaluate this at `time - dt` too.
    private static func pose(scenario: MockScenario, handType: HandType, time: TimeInterval) -> MockHandPose? {
        switch scenario {
        case .noHands:
            return nil
        case .idleRightHand:
            guard handType == .right else { return nil }
            return idlePose(time: time, lateralOffset: 0)
        case .bothHandsIdle:
            return idlePose(time: time, lateralOffset: handType == .right ? 90 : -90)
        case .openClose:
            guard handType == .right else { return nil }
            return openClosePose(time: time)
        case .pinch:
            guard handType == .right else { return nil }
            return pinchPose(time: time)
        case .wave:
            guard handType == .right else { return nil }
            return wavePose(time: time)
        }
    }

    // A relaxed, gently swaying hand.
    private static func idlePose(time: TimeInterval, lateralOffset: Float) -> MockHandPose {
        let t = Float(time)
        let position = Vector3(
            lateralOffset + sin(t * 0.6) * 4,
            180 + cos(t * 0.4) * 3,
            30
        )
        return MockHandPose(position: position, orientation: .identity, curl: SIMD4(repeating: 0.1), thumbCurl: 0.15)
    }

    // Cycles every 2 seconds between a fully open hand and a closed fist.
    private static func openClosePose(time: TimeInterval) -> MockHandPose {
        let cycle = cycle(time: time, period: 2)
        return MockHandPose(position: Vector3(0, 200, 40), orientation: .identity,
                            curl: SIMD4(repeating: cycle), thumbCurl: cycle * 0.8)
    }

    // Cycles the thumb and index finger together into a pinch every 2 seconds,
    // while the other fingers stay loosely curled.
    private static func pinchPose(time: TimeInterval) -> MockHandPose {
        let cycle = cycle(time: time, period: 2)
        return MockHandPose(position: Vector3(0, 180, 30), orientation: .identity,
                            curl: SIMD4(cycle, 0.15, 0.15, 0.15), thumbCurl: cycle)
    }

    // Sweeps the palm from side to side once per second.
    private static func wavePose(time: TimeInterval) -> MockHandPose {
        let t = Float(time)
        let position = Vector3(sin(t * 2 * .pi) * 80, 200, 30)
        return MockHandPose(position: position, orientation: .identity, curl: SIMD4(repeating: 0.1), thumbCurl: 0.1)
    }

    // A value that rises from 0 to 1 and back over `period` seconds.
    private static func cycle(time: TimeInterval, period: TimeInterval) -> Float {
        (sin(2 * Float.pi * Float(time / period)) + 1) / 2
    }

    // MARK: Skeleton Assembly

    // Local-space bone lengths, widths, and curl range for one finger, plus
    // where it attaches to the palm. Defined for the right hand; ``mirrored(_:for:)``
    // reflects it across X for the left.
    private struct FingerSpec {
        /// Where the metacarpal starts, relative to the palm center.
        let root: Vector3
        /// The finger's unit direction before any curl is applied.
        let direction: Vector3
        /// Bone lengths in order: metacarpal, proximal, intermediate, distal.
        let lengths: SIMD4<Float>
        /// Bone widths in the same order.
        let widths: SIMD4<Float>
        /// Maximum flexion angle at each of the three curling joints — MCP
        /// (knuckle), PIP, and DIP — reached at `curl == 1`.
        let jointMax: SIMD3<Float>
        /// The axis each joint's flexion rotates around. The same for all
        /// three curling joints.
        let flexAxis: Vector3
        /// An extra rotation applied once, before flexion, scaled directly by
        /// `curl` (not per joint). Zero for the four fingers; for the thumb
        /// this swings the whole chain across the palm toward the index
        /// finger as it curls (opposition), which is what lets the pinch
        /// scenario actually bring the fingertips together — flexion alone
        /// only closes the gap in two of three axes, since rotating around a
        /// fixed axis can never change position along that axis.
        let oppositionAxis: Vector3
        let oppositionMax: Float
    }

    // The local-hand forward axis: palm center toward fingertips.
    private static let referenceForward = Vector3(0, 1, 0)
    // The lateral axis the four fingers (and the thumb's flexion) curl around.
    private static let lateralAxis = Vector3(1, 0, 0)

    // Builds one finger's bone chain and transforms it into world space.
    //
    // Every spec describes the right hand. For the left hand, `mirror`
    // reflects each computed point and direction across X = 0 as it goes,
    // rather than trying to mirror the rotation math that derives them —
    // reflecting a rotation's axis without also flipping the angle it turns
    // through changes its handedness, not just its placement, which is a easy
    // mistake to make and hard to spot without a test like
    // `leftHandMirrorsRightHandAcrossXAxis`. Mirroring the output instead
    // sidesteps that entirely: if P(i+1) = P(i) + d(i), then reflecting both
    // sides gives M(P(i+1)) = M(P(i)) + M(d(i)), so reflecting the root once
    // and each step's direction as it's produced yields exactly the mirror
    // image at every joint, by induction — independent of how `d(i)` itself
    // was computed.
    //
    // Bones curl by rotating the local direction around `flexAxis`,
    // cumulatively at each joint: metacarpal is unrotated, proximal picks up
    // the MCP angle, intermediate adds PIP, distal adds DIP. The thumb also
    // gets a one-time opposition rotation applied first (see `FingerSpec`).
    private static func finger(spec: FingerSpec, curl: Float, pose: MockHandPose, fingerId: Int32, mirror: Bool) -> Finger {
        let angles = spec.jointMax * curl
        let cumulative = SIMD4<Float>(0, angles.x, angles.x + angles.y, angles.x + angles.y + angles.z)
        let opposition = simd_quatf(angle: spec.oppositionMax * curl, axis: spec.oppositionAxis)
        let baseRotation = opposition * Quaternion(from: referenceForward, to: spec.direction)
        let sign: Float = mirror ? -1 : 1

        var previousJoint = Vector3(spec.root.x * sign, spec.root.y, spec.root.z)
        var bones: [Bone] = []
        bones.reserveCapacity(4)
        for i in 0..<4 {
            let flexRotation = simd_quatf(angle: -cumulative[i], axis: spec.flexAxis)
            let rotatedDirection = (flexRotation * baseRotation).act(referenceForward)
            let localDirection = Vector3(rotatedDirection.x * sign, rotatedDirection.y, rotatedDirection.z)
            let nextJoint = previousJoint + localDirection * spec.lengths[i]

            bones.append(Bone(
                previousJoint: worldPoint(previousJoint, pose: pose),
                nextJoint: worldPoint(nextJoint, pose: pose),
                width: spec.widths[i],
                rotation: pose.orientation * safeRotation(from: referenceForward, to: localDirection)
            ))
            previousJoint = nextJoint
        }

        return Finger(
            id: fingerId,
            metacarpal: bones[0],
            proximal: bones[1],
            intermediate: bones[2],
            distal: bones[3],
            isExtended: curl < 0.4
        )
    }

    // `Quaternion(from:to:)` has no unique answer when the two vectors are
    // antiparallel; picks an arbitrary perpendicular axis in that case rather
    // than risk propagating NaN into a bone's orientation.
    private static func safeRotation(from reference: Vector3, to direction: Vector3) -> Quaternion {
        guard simd_length(direction) > .ulpOfOne else { return .identity }
        let unit = normalize(direction)
        guard simd_dot(reference, unit) > -0.9999 else {
            let axis = abs(reference.x) < 0.9 ? simd_cross(reference, Vector3(1, 0, 0)) : simd_cross(reference, Vector3(0, 1, 0))
            return simd_quatf(angle: .pi, axis: normalize(axis))
        }
        return Quaternion(from: reference, to: unit)
    }

    private static func palm(pose: MockHandPose) -> Palm {
        let position = worldPoint(.zero, pose: pose)
        return Palm(
            position: position,
            stabilizedPosition: position,
            velocity: .zero,
            normal: pose.orientation.act(Vector3(0, 0, -1)),
            direction: pose.orientation.act(referenceForward),
            orientation: pose.orientation,
            width: palmWidth
        )
    }

    // The forearm: from the elbow (250 mm posterior to the wrist) to the wrist.
    private static func arm(pose: MockHandPose) -> Bone {
        let wristLocal = Vector3(0, -20, 0)
        let elbowLocal = wristLocal + Vector3(0, -1, 0) * armLength
        return Bone(
            previousJoint: worldPoint(elbowLocal, pose: pose),
            nextJoint: worldPoint(wristLocal, pose: pose),
            width: armWidth,
            rotation: pose.orientation
        )
    }

    private static func worldPoint(_ local: Vector3, pose: MockHandPose) -> Vector3 {
        pose.orientation.act(local) + pose.position
    }

    private static func unitClamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func defaultId(for type: HandType) -> UInt32 {
        type == .right ? 1 : 2
    }

    // Rebuilds a hand with palm velocity and visible-time filled in, since
    // `hand(type:id:pose:)` has no timeline to derive them from.
    private static func withRuntimeState(_ hand: Hand, velocity: Vector3, visibleTime: UInt64) -> Hand {
        let palm = Palm(
            position: hand.palm.position,
            stabilizedPosition: hand.palm.stabilizedPosition,
            velocity: velocity,
            normal: hand.palm.normal,
            direction: hand.palm.direction,
            orientation: hand.palm.orientation,
            width: hand.palm.width
        )
        return Hand(
            id: hand.id,
            type: hand.type,
            confidence: hand.confidence,
            visibleTime: visibleTime,
            pinchDistance: hand.pinchDistance,
            grabAngle: hand.grabAngle,
            pinchStrength: hand.pinchStrength,
            grabStrength: hand.grabStrength,
            palm: palm,
            thumb: hand.thumb,
            index: hand.index,
            middle: hand.middle,
            ring: hand.ring,
            pinky: hand.pinky,
            arm: hand.arm,
            isPinching: hand.isPinching
        )
    }

    // MARK: Constants

    private static func deg(_ degrees: Float) -> Float { degrees * .pi / 180 }

    private static let palmWidth: Float = 85
    private static let armWidth: Float = 40
    private static let armLength: Float = 250
    private static let pinchOpenDistance: Float = 60
    private static let pinchClosedDistance: Float = 20
    private static let maxGrabAngle: Float = 2.6

    private static let thumbSpec = FingerSpec(
        root: Vector3(28, -12, 10),
        direction: normalize(Vector3(0.55, 0.65, 0.45)),
        lengths: SIMD4(0, 40, 32, 24),
        widths: SIMD4(18, 18, 15, 12),
        jointMax: SIMD3(deg(50), deg(60), deg(50)),
        flexAxis: lateralAxis,
        oppositionAxis: Vector3(0, 0, 1),
        oppositionMax: deg(40)
    )
    private static let indexSpec = FingerSpec(
        root: Vector3(30, 12, 0),
        direction: normalize(Vector3(0.15, 1, 0)),
        lengths: SIMD4(68, 39, 22, 16),
        widths: SIMD4(20, 17, 14, 11),
        jointMax: SIMD3(deg(90), deg(100), deg(70)),
        flexAxis: lateralAxis,
        oppositionAxis: lateralAxis,
        oppositionMax: 0
    )
    private static let middleSpec = FingerSpec(
        root: Vector3(9, 17, 0),
        direction: Vector3(0, 1, 0),
        lengths: SIMD4(65, 45, 26, 18),
        widths: SIMD4(21, 18, 15, 12),
        jointMax: SIMD3(deg(95), deg(105), deg(75)),
        flexAxis: lateralAxis,
        oppositionAxis: lateralAxis,
        oppositionMax: 0
    )
    private static let ringSpec = FingerSpec(
        root: Vector3(-10, 15, 0),
        direction: normalize(Vector3(-0.12, 1, 0)),
        lengths: SIMD4(58, 41, 25, 17),
        widths: SIMD4(19, 16, 13, 10),
        jointMax: SIMD3(deg(90), deg(100), deg(70)),
        flexAxis: lateralAxis,
        oppositionAxis: lateralAxis,
        oppositionMax: 0
    )
    private static let pinkySpec = FingerSpec(
        root: Vector3(-27, 10, 0),
        direction: normalize(Vector3(-0.28, 1, 0)),
        lengths: SIMD4(53, 32, 18, 15),
        widths: SIMD4(16, 13, 11, 9),
        jointMax: SIMD3(deg(85), deg(95), deg(65)),
        flexAxis: lateralAxis,
        oppositionAxis: lateralAxis,
        oppositionMax: 0
    )
}
