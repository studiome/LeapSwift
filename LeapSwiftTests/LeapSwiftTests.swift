//
//  LeapSwiftTests.swift
//  LeapSwiftTests
//

import Testing
import simd
import LeapC
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

// MARK: - Device Open Policy Tests

@Suite("Device open policy")
struct DeviceOpenPolicyTests {

    // The service does not enumerate the device until after it emits its device
    // event: polling right after `connected` reports zero devices, and the device
    // only appears ~40 ms later alongside `deviceFound`. Opening on `connected`
    // alone therefore always misses it.
    @Test func opensOnDeviceFound() {
        #expect(LeapController.shouldOpenDevice(for: .deviceFound(nil)))
    }

    @Test func opensOnConnected() {
        #expect(LeapController.shouldOpenDevice(for: .connected))
    }

    @Test func doesNotOpenOnUnrelatedEvents() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(!LeapController.shouldOpenDevice(for: .disconnected))
        #expect(!LeapController.shouldOpenDevice(for: .deviceLost))
        #expect(!LeapController.shouldOpenDevice(for: .trackingFrame(frame)))
    }

    // Reporting a failure must not itself trigger another open attempt.
    @Test func doesNotOpenOnError() {
        #expect(!LeapController.shouldOpenDevice(for: .error(.deviceNotFound)))
        #expect(!LeapController.shouldCloseDevice(for: .error(.deviceNotFound)))
    }

    // Missing devices are only a failure when the service said one appeared.
    @Test func onlyDeviceFoundPromisesAnEnumerableDevice() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(LeapController.expectsDeviceToBePresent(for: .deviceFound(nil)))
        #expect(!LeapController.expectsDeviceToBePresent(for: .connected))
        #expect(!LeapController.expectsDeviceToBePresent(for: .disconnected))
        #expect(!LeapController.expectsDeviceToBePresent(for: .deviceLost))
        #expect(!LeapController.expectsDeviceToBePresent(for: .trackingFrame(frame)))
        #expect(!LeapController.expectsDeviceToBePresent(for: .error(.deviceNotFound)))
    }

    // A lost device must release the handle so a later reconnect can open again.
    @Test func closesOnDeviceLost() {
        let frame = HandFrame(frameId: 0, timestamp: 0, hands: [], frameRate: 0)
        #expect(LeapController.shouldCloseDevice(for: .deviceLost))
        #expect(!LeapController.shouldCloseDevice(for: .connected))
        #expect(!LeapController.shouldCloseDevice(for: .deviceFound(nil)))
        #expect(!LeapController.shouldCloseDevice(for: .trackingFrame(frame)))
    }
}

// MARK: - Device Info Tests

@Suite("DeviceInfo")
struct DeviceInfoTests {

    // The public initializer exists so mocks and tests can construct device
    // info directly; the only other way to get one is the failable init from
    // a live LEAP_DEVICE_INFO, which needs a real device.
    @Test func memberwiseInitializerStoresAllFields() {
        let info = DeviceInfo(serialNumber: "LM-000000", horizontalFOV: 2.3, verticalFOV: 2.0, range: 600_000, baseline: 40_000)
        #expect(info.serialNumber == "LM-000000")
        #expect(info.horizontalFOV == 2.3)
        #expect(info.verticalFOV == 2.0)
        #expect(info.range == 600_000)
        #expect(info.baseline == 40_000)
    }
}

// MARK: - Frozen Enum Tests

@Suite("Frozen enums")
struct FrozenEnumTests {

    // HandType and VersionPart are @frozen, so an exhaustive switch compiles
    // without `@unknown default` even from outside the framework. These switches
    // fail to build if the attribute is ever removed.
    @Test func handTypeSwitchesExhaustively() {
        func name(_ t: HandType) -> String {
            switch t {
            case .left:  "left"
            case .right: "right"
            }
        }
        #expect(name(.left) == "left")
        #expect(name(.right) == "right")
    }

    @Test func versionPartSwitchesExhaustively() {
        func name(_ p: VersionPart) -> String {
            switch p {
            case .clientLibrary:  "clientLibrary"
            case .clientProtocol: "clientProtocol"
            case .serverLibrary:  "serverLibrary"
            case .serverProtocol: "serverProtocol"
            }
        }
        #expect(name(.serverLibrary) == "serverLibrary")
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
            .policyError(0)
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

    // eLeapRS_NotConnected (0xE2010005) exceeds Int32.max, so the raw enum's
    // bit pattern must be preserved with Int32(bitPattern:) rather than
    // truncated with Int32(_:), which traps on overflow.
    @Test func initFromNotConnectedPreservesBitPattern() {
        let error = LeapError(eLeapRS_NotConnected)
        guard case .connectionFailed(let code) = error else {
            Issue.record("Expected .connectionFailed, got \(error)")
            return
        }
        #expect(code == Int32(bitPattern: eLeapRS_NotConnected.rawValue))
        #expect(error.errorDescription?.contains("e2010005") == true)
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

// MARK: - Palm Orientation Tests

@Suite("Palm orientation (roll / pitch / yaw)")
struct PalmOrientationTests {

    private static let eps: Float = 1e-5

    private func makePalm(normal: Vector3 = .zero, direction: Vector3 = .zero) -> Palm {
        Palm(position: .zero, stabilizedPosition: .zero, velocity: .zero,
             normal: normal, direction: direction, orientation: .identity, width: 0)
    }

    // MARK: Roll — atan2(normal.x, -normal.y)

    @Test func rollIsZeroWhenPalmFacesDown() {
        // normal = (0, -1, 0) → atan2(0, 1) = 0
        let palm = makePalm(normal: .init(0, -1, 0))
        #expect(abs(palm.roll) < Self.eps)
    }

    @Test func rollIsHalfPiWhenPalmFacesRight() {
        // normal = (1, 0, 0) → atan2(1, 0) = π/2
        let palm = makePalm(normal: .init(1, 0, 0))
        #expect(abs(palm.roll - .pi / 2) < Self.eps)
    }

    @Test func rollIsNegativeHalfPiWhenPalmFacesLeft() {
        // normal = (-1, 0, 0) → atan2(-1, 0) = -π/2
        let palm = makePalm(normal: .init(-1, 0, 0))
        #expect(abs(palm.roll + .pi / 2) < Self.eps)
    }

    // MARK: Pitch — atan2(direction.y, -direction.z)

    @Test func pitchIsZeroWhenPointingForward() {
        // direction = (0, 0, -1) → atan2(0, 1) = 0
        let palm = makePalm(direction: .init(0, 0, -1))
        #expect(abs(palm.pitch) < Self.eps)
    }

    @Test func pitchIsHalfPiWhenPointingUp() {
        // direction = (0, 1, 0) → atan2(1, 0) = π/2
        let palm = makePalm(direction: .init(0, 1, 0))
        #expect(abs(palm.pitch - .pi / 2) < Self.eps)
    }

    @Test func pitchIsNegativeHalfPiWhenPointingDown() {
        // direction = (0, -1, 0) → atan2(-1, 0) = -π/2
        let palm = makePalm(direction: .init(0, -1, 0))
        #expect(abs(palm.pitch + .pi / 2) < Self.eps)
    }

    // MARK: Yaw — atan2(direction.x, -direction.z)

    @Test func yawIsZeroWhenPointingForward() {
        // direction = (0, 0, -1) → atan2(0, 1) = 0
        let palm = makePalm(direction: .init(0, 0, -1))
        #expect(abs(palm.yaw) < Self.eps)
    }

    @Test func yawIsHalfPiWhenPointingRight() {
        // direction = (1, 0, 0) → atan2(1, 0) = π/2
        let palm = makePalm(direction: .init(1, 0, 0))
        #expect(abs(palm.yaw - .pi / 2) < Self.eps)
    }

    @Test func yawIsNegativeHalfPiWhenPointingLeft() {
        // direction = (-1, 0, 0) → atan2(-1, 0) = -π/2
        let palm = makePalm(direction: .init(-1, 0, 0))
        #expect(abs(palm.yaw + .pi / 2) < Self.eps)
    }

    // MARK: Hand convenience properties delegate to palm

    @Test func handRollPitchYawDelegateToPalm() {
        let bone = Bone(previousJoint: .zero, nextJoint: .zero, width: 0, rotation: .identity)
        let finger = Finger(id: 0, metacarpal: bone, proximal: bone, intermediate: bone, distal: bone, isExtended: false)
        let palm = makePalm(normal: .init(0.5, -0.5, 0), direction: .init(0.5, 0.5, -1))
        let hand = Hand(id: 1, type: .right, confidence: 1, visibleTime: 0,
                        pinchDistance: 0, grabAngle: 0, pinchStrength: 0, grabStrength: 0,
                        palm: palm, thumb: finger, index: finger, middle: finger,
                        ring: finger, pinky: finger, arm: bone, isPinching: false)
        #expect(hand.roll == palm.roll)
        #expect(hand.pitch == palm.pitch)
        #expect(hand.yaw == palm.yaw)
    }
}
