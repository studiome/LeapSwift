//
//  LeapSwiftTests.swift
//  LeapSwiftTests
//

import Testing
import simd
@testable import LeapSwift

// MARK: - Bone Tests

@Suite("Bone")
struct BoneTests {

    @Test func centerIsMidpointOfJoints() {
        let bone = Bone(
            previousJoint: .init(0, 0, 0),
            nextJoint: .init(10, 0, 0),
            width: 0,
            rotation: .identity
        )
        #expect(bone.center == SIMD3<Float>(5, 0, 0))
    }

    @Test func lengthIsDistanceBetweenJoints() {
        // 3-4-5 right triangle → length == 5
        let bone = Bone(
            previousJoint: .init(0, 0, 0),
            nextJoint: .init(3, 4, 0),
            width: 0,
            rotation: .identity
        )
        #expect(abs(bone.length - 5.0) < 0.001)
    }

    @Test func zeroLengthWhenJointsCoincide() {
        let bone = Bone(
            previousJoint: .init(1, 2, 3),
            nextJoint: .init(1, 2, 3),
            width: 0,
            rotation: .identity
        )
        #expect(bone.length == 0.0)
    }
}

// MARK: - Finger Tests

@Suite("Finger")
struct FingerTests {

    private func makeBone(from: Vector3 = .zero, to: Vector3 = .zero) -> Bone {
        Bone(previousJoint: from, nextJoint: to, width: 0, rotation: .identity)
    }

    @Test func tipPositionIsDistalNextJoint() {
        let tip = Vector3(1, 2, 3)
        let distal = makeBone(from: .zero, to: tip)
        let finger = Finger(
            id: 1,
            metacarpal: makeBone(),
            proximal: makeBone(),
            intermediate: makeBone(),
            distal: distal,
            isExtended: true
        )
        #expect(finger.tipPosition == tip)
    }

    @Test func bonesContainsFourElements() {
        let zero = makeBone()
        let finger = Finger(id: 0, metacarpal: zero, proximal: zero, intermediate: zero, distal: zero, isExtended: false)
        #expect(finger.bones.count == 4)
    }

    @Test func bonesOrderIsMetaProximalIntermediateDistal() {
        let meta  = makeBone(to: .init(1, 0, 0))
        let prox  = makeBone(to: .init(2, 0, 0))
        let inter = makeBone(to: .init(3, 0, 0))
        let dist  = makeBone(to: .init(4, 0, 0))
        let finger = Finger(id: 0, metacarpal: meta, proximal: prox, intermediate: inter, distal: dist, isExtended: true)
        #expect(finger.bones[0].nextJoint == .init(1, 0, 0))
        #expect(finger.bones[1].nextJoint == .init(2, 0, 0))
        #expect(finger.bones[2].nextJoint == .init(3, 0, 0))
        #expect(finger.bones[3].nextJoint == .init(4, 0, 0))
    }
}

// MARK: - HandFrame Tests

@Suite("HandFrame")
struct HandFrameTests {

    private func makeHand(id: UInt32, type: HandType) -> Hand {
        let bone   = Bone(previousJoint: .zero, nextJoint: .zero, width: 0, rotation: .identity)
        let finger = Finger(id: 0, metacarpal: bone, proximal: bone, intermediate: bone, distal: bone, isExtended: false)
        let palm   = Palm(position: .zero, stabilizedPosition: .zero, velocity: .zero,
                          normal: .zero, direction: .zero, orientation: .identity, width: 0)
        return Hand(id: id, type: type, confidence: 1, visibleTime: 0,
                    pinchDistance: 0, grabAngle: 0, pinchStrength: 0, grabStrength: 0,
                    palm: palm, thumb: finger, index: finger, middle: finger,
                    ring: finger, pinky: finger, arm: bone, isPinching: false)
    }

    @Test func emptyFrameHasNoHands() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(frame.hands.isEmpty)
        #expect(frame.leftHand == nil)
        #expect(frame.rightHand == nil)
    }

    @Test func leftHandDetected() {
        let frame = HandFrame(frameId: 1, timestamp: 1000, hands: [makeHand(id: 1, type: .left)], frameRate: 60)
        #expect(frame.leftHand?.id == 1)
        #expect(frame.rightHand == nil)
    }

    @Test func rightHandDetected() {
        let frame = HandFrame(frameId: 2, timestamp: 2000, hands: [makeHand(id: 2, type: .right)], frameRate: 60)
        #expect(frame.rightHand?.id == 2)
        #expect(frame.leftHand == nil)
    }

    @Test func bothHandsDetected() {
        let left  = makeHand(id: 1, type: .left)
        let right = makeHand(id: 2, type: .right)
        let frame = HandFrame(frameId: 3, timestamp: 3000, hands: [left, right], frameRate: 60)
        #expect(frame.leftHand?.id == 1)
        #expect(frame.rightHand?.id == 2)
    }

    @Test func handHasFiveFingers() {
        let hand = makeHand(id: 1, type: .left)
        #expect(hand.fingers.count == 5)
    }
}

// MARK: - LeapError Tests

@Suite("LeapError")
struct LeapErrorTests {

    @Test func allErrorsHaveNonEmptyDescription() {
        let errors: [LeapError] = [
            .connectionFailed(0),
            .deviceNotFound,
            .openDeviceFailed(0),
            .policyError(0),
            .trackingUnavailable
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false, "Description missing for \(error)")
        }
    }

    @Test func deviceNotFoundDescription() {
        let error = LeapError.deviceNotFound
        #expect(error.errorDescription?.contains("device") == true ||
                error.errorDescription?.contains("Device") == true)
    }
}

// MARK: - TrackingMode Tests

@Suite("TrackingMode")
struct TrackingModeTests {

    @Test func desktopRoundTrip() {
        let mode = TrackingMode.desktop
        #expect(TrackingMode(mode.cValue) == mode)
    }

    @Test func headMountedRoundTrip() {
        let mode = TrackingMode.headMounted
        #expect(TrackingMode(mode.cValue) == mode)
    }

    @Test func screenTopRoundTrip() {
        let mode = TrackingMode.screenTop
        #expect(TrackingMode(mode.cValue) == mode)
    }
}

// MARK: - HandType Tests

@Suite("HandType")
struct HandTypeTests {

    @Test func handTypeEquality() {
        #expect(HandType.left == HandType.left)
        #expect(HandType.right == HandType.right)
        #expect(HandType.left != HandType.right)
    }
}
