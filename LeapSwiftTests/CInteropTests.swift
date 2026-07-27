//
//  CInteropTests.swift
//  LeapSwiftTests
//
//  Verifies the C struct → Swift value type conversion initializers in
//  Types.swift, and LeapController.convertMessage's C message → LeapEvent
//  mapping. All of these run without a device or the Ultraleap service —
//  they only need hand-built LEAP_* structs.
//

import Testing
import simd
import LeapC
@testable import LeapSwift

// MARK: - LEAP_VECTOR / LEAP_QUATERNION

@Suite("Vector3 from LEAP_VECTOR")
struct Vector3FromLeapVectorTests {

    @Test func componentsMapStraightThrough() {
        var v = LEAP_VECTOR()
        v.x = 1
        v.y = 2
        v.z = 3
        #expect(Vector3(v) == Vector3(1, 2, 3))
    }
}

@Suite("Quaternion from LEAP_QUATERNION")
struct QuaternionFromLeapQuaternionTests {

    // LEAP's x/y/z/w must land on simd_quatf's ix/iy/iz/r respectively — mixing
    // up w and any of x/y/z would silently corrupt every bone and palm rotation.
    @Test func componentsMapToImaginaryAndRealParts() {
        var q = LEAP_QUATERNION()
        q.x = 0.1
        q.y = 0.2
        q.z = 0.3
        q.w = 0.4
        let quat = Quaternion(q)
        #expect(quat.imag.x == Float(0.1))
        #expect(quat.imag.y == Float(0.2))
        #expect(quat.imag.z == Float(0.3))
        #expect(quat.real == Float(0.4))
    }
}

// MARK: - LEAP_BONE

@Suite("Bone from LEAP_BONE")
struct BoneFromLeapBoneTests {

    @Test func fieldsMapStraightThrough() {
        var prev = LEAP_VECTOR()
        prev.x = 1; prev.y = 2; prev.z = 3
        var next = LEAP_VECTOR()
        next.x = 4; next.y = 5; next.z = 6
        var rot = LEAP_QUATERNION()
        rot.x = 0; rot.y = 0; rot.z = 0; rot.w = 1

        var b = LEAP_BONE()
        b.prev_joint = prev
        b.next_joint = next
        b.width = 12.5
        b.rotation = rot

        let bone = Bone(b)
        #expect(bone.previousJoint == Vector3(1, 2, 3))
        #expect(bone.nextJoint == Vector3(4, 5, 6))
        #expect(bone.width == 12.5)
        #expect(bone.rotation == Quaternion.identity)
    }
}

// MARK: - LEAP_DIGIT

@Suite("Finger from LEAP_DIGIT")
struct FingerFromLeapDigitTests {

    private func makeLeapBone(nextX: Float) -> LEAP_BONE {
        var next = LEAP_VECTOR()
        next.x = nextX
        var b = LEAP_BONE()
        b.next_joint = next
        return b
    }

    // The bones tuple must map metacarpal → proximal → intermediate → distal,
    // in that order — the same order LEAP_DIGIT's anonymous struct declares
    // them, and the order Finger's own `bones` accessor documents.
    @Test func bonesTupleOrderIsMetacarpalProximalIntermediateDistal() {
        var d = LEAP_DIGIT()
        d.finger_id = 7
        d.bones = (
            makeLeapBone(nextX: 1),
            makeLeapBone(nextX: 2),
            makeLeapBone(nextX: 3),
            makeLeapBone(nextX: 4)
        )
        d.is_extended = 1

        let finger = Finger(d)
        #expect(finger.id == 7)
        #expect(finger.metacarpal.nextJoint.x == 1)
        #expect(finger.proximal.nextJoint.x == 2)
        #expect(finger.intermediate.nextJoint.x == 3)
        #expect(finger.distal.nextJoint.x == 4)
        #expect(finger.isExtended)
    }

    @Test func isExtendedFalseWhenZero() {
        var d = LEAP_DIGIT()
        d.is_extended = 0
        #expect(!Finger(d).isExtended)
    }
}

// MARK: - LEAP_PALM

@Suite("Palm from LEAP_PALM")
struct PalmFromLeapPalmTests {

    @Test func fieldsMapStraightThrough() {
        func vec(_ x: Float) -> LEAP_VECTOR {
            var v = LEAP_VECTOR()
            v.x = x; v.y = x; v.z = x
            return v
        }
        var orientation = LEAP_QUATERNION()
        orientation.w = 1

        var p = LEAP_PALM()
        p.position = vec(1)
        p.stabilized_position = vec(2)
        p.velocity = vec(3)
        p.normal = vec(4)
        p.direction = vec(5)
        p.orientation = orientation
        p.width = 42

        let palm = Palm(p)
        #expect(palm.position == Vector3(1, 1, 1))
        #expect(palm.stabilizedPosition == Vector3(2, 2, 2))
        #expect(palm.velocity == Vector3(3, 3, 3))
        #expect(palm.normal == Vector3(4, 4, 4))
        #expect(palm.direction == Vector3(5, 5, 5))
        #expect(palm.orientation == Quaternion.identity)
        #expect(palm.width == 42)
    }
}

// MARK: - LEAP_HAND

@Suite("Hand from LEAP_HAND")
struct HandFromLeapHandTests {

    private func makeLeapDigit(id: Int32) -> LEAP_DIGIT {
        var d = LEAP_DIGIT()
        d.finger_id = id
        d.bones = (LEAP_BONE(), LEAP_BONE(), LEAP_BONE(), LEAP_BONE())
        return d
    }

    // The digits tuple must map thumb → index → middle → ring → pinky, in that
    // order — the same order LEAP_HAND's anonymous struct declares them.
    @Test func digitsTupleOrderIsThumbIndexMiddleRingPinky() {
        var h = LEAP_HAND()
        h.digits = (
            makeLeapDigit(id: 1),
            makeLeapDigit(id: 2),
            makeLeapDigit(id: 3),
            makeLeapDigit(id: 4),
            makeLeapDigit(id: 5)
        )

        let hand = Hand(h)
        #expect(hand.thumb.id == 1)
        #expect(hand.index.id == 2)
        #expect(hand.middle.id == 3)
        #expect(hand.ring.id == 4)
        #expect(hand.pinky.id == 5)
    }

    @Test func typeMapsLeftAndRight() {
        var h = LEAP_HAND()
        h.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())

        h.type = eLeapHandType_Left
        #expect(Hand(h).type == .left)

        h.type = eLeapHandType_Right
        #expect(Hand(h).type == .right)
    }

    @Test func scalarFieldsMapStraightThrough() {
        var h = LEAP_HAND()
        h.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())
        h.id = 99
        h.confidence = 1
        h.visible_time = 123_456
        h.pinch_distance = 10
        h.grab_angle = 0.5
        h.pinch_strength = 0.25
        h.grab_strength = 0.75

        let hand = Hand(h)
        #expect(hand.id == 99)
        #expect(hand.confidence == 1)
        #expect(hand.visibleTime == 123_456)
        #expect(hand.pinchDistance == 10)
        #expect(hand.grabAngle == 0.5)
        #expect(hand.pinchStrength == 0.25)
        #expect(hand.grabStrength == 0.75)
    }

    // The pinch bit in `flags` must set isPinching; every other bit must leave
    // it false, since callers branch on this for gesture detection.
    @Test func isPinchingReflectsGesturePinchFlag() {
        var h = LEAP_HAND()
        h.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())

        h.flags = UInt32(eLeapHandFlag_GesturePinch.rawValue)
        #expect(Hand(h).isPinching)

        h.flags = 0
        #expect(!Hand(h).isPinching)

        h.flags = UInt32(eLeapHandFlag_GestureDetectionAvailable.rawValue)
        #expect(!Hand(h).isPinching)
    }
}

// MARK: - LEAP_TRACKING_EVENT

@Suite("HandFrame from LEAP_TRACKING_EVENT")
struct HandFrameFromLeapTrackingEventTests {

    @Test func fieldsMapStraightThroughWithOneHand() {
        var hand = LEAP_HAND()
        hand.id = 5
        hand.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())

        withUnsafeMutablePointer(to: &hand) { p in
            var event = LEAP_TRACKING_EVENT()
            event.info.frame_id = 42
            event.info.timestamp = 1_000
            event.framerate = 90
            event.pHands = p
            event.nHands = 1

            let frame = HandFrame(event)
            #expect(frame.frameId == 42)
            #expect(frame.timestamp == 1_000)
            #expect(frame.frameRate == 90)
            #expect(frame.hands.count == 1)
            #expect(frame.hands.first?.id == 5)
        }
    }

    @Test func noHandsWhenPointerIsNil() {
        var event = LEAP_TRACKING_EVENT()
        event.pHands = nil
        event.nHands = 0
        #expect(HandFrame(event).hands.isEmpty)
    }

    @Test func noHandsWhenCountIsZeroEvenIfPointerIsSet() {
        var hand = LEAP_HAND()
        hand.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())
        withUnsafeMutablePointer(to: &hand) { p in
            var event = LEAP_TRACKING_EVENT()
            event.pHands = p
            event.nHands = 0
            #expect(HandFrame(event).hands.isEmpty)
        }
    }
}

// MARK: - LEAP_DEVICE_INFO

@Suite("DeviceInfo from LEAP_DEVICE_INFO")
struct DeviceInfoFromLeapDeviceInfoTests {

    @Test func fieldsMapStraightThrough() {
        var serial: [CChar] = Array("ABC123\0".utf8CString)
        serial.withUnsafeMutableBufferPointer { buf in
            var info = LEAP_DEVICE_INFO()
            info.serial = buf.baseAddress
            info.serial_length = UInt32(buf.count)
            info.h_fov = 2.3
            info.v_fov = 2.0
            info.range = 600_000
            info.baseline = 40_000

            let deviceInfo = DeviceInfo(info)
            #expect(deviceInfo?.serialNumber == "ABC123")
            #expect(deviceInfo?.horizontalFOV == 2.3)
            #expect(deviceInfo?.verticalFOV == 2.0)
            #expect(deviceInfo?.range == 600_000)
            #expect(deviceInfo?.baseline == 40_000)
        }
    }

    // The failable initializer exists specifically for this case: LeapGetDeviceInfo
    // is called once with `info.serial = nil` just to learn the buffer length.
    @Test func nilWhenSerialPointerIsMissing() {
        var info = LEAP_DEVICE_INFO()
        info.serial = nil
        #expect(DeviceInfo(info) == nil)
    }
}

// MARK: - convertMessage

@Suite("LeapController.convertMessage")
struct ConvertMessageTests {

    @Test func connectionMapsToConnected() {
        var msg = LEAP_CONNECTION_MESSAGE()
        msg.type = eLeapEventType_Connection
        guard case .connected = LeapController.convertMessage(msg) else {
            Issue.record("Expected .connected")
            return
        }
    }

    @Test func connectionLostMapsToDisconnected() {
        var msg = LEAP_CONNECTION_MESSAGE()
        msg.type = eLeapEventType_ConnectionLost
        guard case .disconnected = LeapController.convertMessage(msg) else {
            Issue.record("Expected .disconnected")
            return
        }
    }

    @Test func deviceMapsToDeviceFoundNil() {
        var msg = LEAP_CONNECTION_MESSAGE()
        msg.type = eLeapEventType_Device
        guard case .deviceFound(let info) = LeapController.convertMessage(msg) else {
            Issue.record("Expected .deviceFound")
            return
        }
        #expect(info == nil)
    }

    @Test func deviceLostMapsToDeviceLost() {
        var msg = LEAP_CONNECTION_MESSAGE()
        msg.type = eLeapEventType_DeviceLost
        guard case .deviceLost = LeapController.convertMessage(msg) else {
            Issue.record("Expected .deviceLost")
            return
        }
    }

    @Test func trackingMapsToTrackingFrame() {
        var hand = LEAP_HAND()
        hand.id = 3
        hand.digits = (LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT(), LEAP_DIGIT())

        withUnsafeMutablePointer(to: &hand) { p in
            var event = LEAP_TRACKING_EVENT()
            event.info.frame_id = 11
            event.info.timestamp = 22
            event.framerate = 90
            event.pHands = p
            event.nHands = 1

            withUnsafePointer(to: event) { eventPtr in
                var msg = LEAP_CONNECTION_MESSAGE()
                msg.type = eLeapEventType_Tracking
                msg.tracking_event = eventPtr

                guard case .trackingFrame(let frame) = LeapController.convertMessage(msg) else {
                    Issue.record("Expected .trackingFrame")
                    return
                }
                #expect(frame.frameId == 11)
                #expect(frame.timestamp == 22)
                #expect(frame.hands.first?.id == 3)
            }
        }
    }

    // Any message type this framework does not recognize must be dropped
    // rather than crash or surface as some other event.
    @Test func unknownTypeMapsToNil() {
        var msg = LEAP_CONNECTION_MESSAGE()
        msg.type = eLeapEventType_None
        #expect(LeapController.convertMessage(msg) == nil)
    }
}
