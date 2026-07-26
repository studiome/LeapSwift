import simd
import LeapC

// MARK: - Math Types

/// A 3D vector using single-precision floats (millimeters in Leap coordinate space).
public typealias Vector3 = SIMD3<Float>

/// A quaternion representing orientation.
public typealias Quaternion = simd_quatf

extension SIMD3 where Scalar == Float {
    init(_ v: LEAP_VECTOR) {
        self.init(v.x, v.y, v.z)
    }
}

extension simd_quatf {
    /// The identity quaternion (no rotation).
    public static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    init(_ q: LEAP_QUATERNION) {
        self.init(ix: q.x, iy: q.y, iz: q.z, r: q.w)
    }
}

// MARK: - Tracking Mode

/// The tracking mode for the Leap Motion device.
public enum TrackingMode: Equatable, Sendable {
    case desktop
    case headMounted
    case screenTop
    case unknown

    var cValue: eLeapTrackingMode {
        switch self {
        case .desktop:     return eLeapTrackingMode_Desktop
        case .headMounted: return eLeapTrackingMode_HMD
        case .screenTop:   return eLeapTrackingMode_ScreenTop
        case .unknown:     return eLeapTrackingMode_Unknown
        }
    }

    init(_ mode: eLeapTrackingMode) {
        switch mode {
        case eLeapTrackingMode_Desktop:   self = .desktop
        case eLeapTrackingMode_HMD:       self = .headMounted
        case eLeapTrackingMode_ScreenTop: self = .screenTop
        default:                          self = .unknown
        }
    }
}

// MARK: - Hand Type

/// Whether the hand is the left or right hand.
public enum HandType: Equatable, Sendable {
    case left
    case right
}

// MARK: - Bone

/// A single bone segment with position and orientation.
public struct Bone: Equatable, Sendable {
    /// The joint closer to the wrist (proximal end).
    public let previousJoint: Vector3
    /// The joint closer to the fingertip (distal end).
    public let nextJoint: Vector3
    /// Average width of flesh around the bone in millimeters.
    public let width: Float
    /// Rotation of the bone in world space.
    public let rotation: Quaternion

    /// Computed center of the bone.
    public var center: Vector3 { (previousJoint + nextJoint) * 0.5 }

    /// Length of the bone in millimeters.
    public var length: Float { simd_distance(previousJoint, nextJoint) }

    /// Designated public initializer — also used for testing and mocking.
    public init(previousJoint: Vector3, nextJoint: Vector3, width: Float, rotation: Quaternion) {
        self.previousJoint = previousJoint
        self.nextJoint = nextJoint
        self.width = width
        self.rotation = rotation
    }

    init(_ bone: LEAP_BONE) {
        self.init(
            previousJoint: Vector3(bone.prev_joint),
            nextJoint: Vector3(bone.next_joint),
            width: bone.width,
            rotation: Quaternion(bone.rotation)
        )
    }
}

// MARK: - Finger

/// A tracked finger with its four bones.
public struct Finger: Equatable, Sendable {
    public let id: Int32
    /// The metacarpal bone (zero-length for the thumb in the Ultraleap model).
    public let metacarpal: Bone
    /// The proximal phalange (nearest the knuckle).
    public let proximal: Bone
    /// The intermediate phalange (middle segment).
    public let intermediate: Bone
    /// The distal phalange (nearest the fingertip).
    public let distal: Bone
    /// Whether the finger is extended (roughly straight).
    public let isExtended: Bool

    /// All four bones in order: metacarpal → proximal → intermediate → distal.
    public var bones: [Bone] { [metacarpal, proximal, intermediate, distal] }

    /// The position of the fingertip (distal next joint).
    public var tipPosition: Vector3 { distal.nextJoint }

    /// Designated public initializer — also used for testing and mocking.
    public init(
        id: Int32,
        metacarpal: Bone,
        proximal: Bone,
        intermediate: Bone,
        distal: Bone,
        isExtended: Bool
    ) {
        self.id = id
        self.metacarpal = metacarpal
        self.proximal = proximal
        self.intermediate = intermediate
        self.distal = distal
        self.isExtended = isExtended
    }

    init(_ digit: LEAP_DIGIT) {
        // C fixed-size arrays import as tuples in Swift
        let b = digit.bones
        self.init(
            id: digit.finger_id,
            metacarpal: Bone(b.0),
            proximal: Bone(b.1),
            intermediate: Bone(b.2),
            distal: Bone(b.3),
            isExtended: digit.is_extended != 0
        )
    }
}

// MARK: - Palm

/// Data about the palm of the hand.
public struct Palm: Equatable, Sendable {
    /// Center of the palm in millimeters from the device origin.
    public let position: Vector3
    /// Time-filtered, stabilized palm position (suitable for 2D UI interaction).
    public let stabilizedPosition: Vector3
    /// Rate of change of palm position in mm/s.
    public let velocity: Vector3
    /// Normal vector pointing out of the palm surface.
    public let normal: Vector3
    /// Unit vector pointing from palm toward the fingers.
    public let direction: Vector3
    /// Quaternion representing the palm's orientation.
    public let orientation: Quaternion
    /// Estimated palm width in millimeters when the hand is flat.
    public let width: Float

    /// Designated public initializer — also used for testing and mocking.
    public init(
        position: Vector3,
        stabilizedPosition: Vector3,
        velocity: Vector3,
        normal: Vector3,
        direction: Vector3,
        orientation: Quaternion,
        width: Float
    ) {
        self.position = position
        self.stabilizedPosition = stabilizedPosition
        self.velocity = velocity
        self.normal = normal
        self.direction = direction
        self.orientation = orientation
        self.width = width
    }

    init(_ palm: LEAP_PALM) {
        self.init(
            position: Vector3(palm.position),
            stabilizedPosition: Vector3(palm.stabilized_position),
            velocity: Vector3(palm.velocity),
            normal: Vector3(palm.normal),
            direction: Vector3(palm.direction),
            orientation: Quaternion(palm.orientation),
            width: palm.width
        )
    }
}

// MARK: - Hand

/// A fully tracked hand with all fingers, palm, and arm data.
public struct Hand: Sendable {
    /// Unique identifier for this hand across frames (stable while the hand is tracked).
    public let id: UInt32
    /// Whether this is the left or right hand.
    public let type: HandType
    /// Tracking confidence (always 1.0 currently).
    public let confidence: Float
    /// Total time this hand has been tracked, in microseconds.
    public let visibleTime: UInt64
    /// Distance between index finger and thumb in millimeters.
    public let pinchDistance: Float
    /// Average angle of fingers to palm in radians.
    public let grabAngle: Float
    /// Normalized pinch strength (0 = open, 1 = fully pinched).
    public let pinchStrength: Float
    /// Normalized grab strength (0 = open, 1 = fully closed fist).
    public let grabStrength: Float
    /// Palm data.
    public let palm: Palm
    /// The thumb.
    public let thumb: Finger
    /// The index finger.
    public let index: Finger
    /// The middle finger.
    public let middle: Finger
    /// The ring finger.
    public let ring: Finger
    /// The pinky finger.
    public let pinky: Finger
    /// The forearm bone.
    public let arm: Bone
    /// Whether a pinch gesture is detected (requires gesture detection license).
    public let isPinching: Bool

    /// All five fingers in order: thumb, index, middle, ring, pinky.
    public var fingers: [Finger] { [thumb, index, middle, ring, pinky] }

    /// Designated public initializer — also used for testing and mocking.
    public init(
        id: UInt32,
        type: HandType,
        confidence: Float,
        visibleTime: UInt64,
        pinchDistance: Float,
        grabAngle: Float,
        pinchStrength: Float,
        grabStrength: Float,
        palm: Palm,
        thumb: Finger,
        index: Finger,
        middle: Finger,
        ring: Finger,
        pinky: Finger,
        arm: Bone,
        isPinching: Bool
    ) {
        self.id = id
        self.type = type
        self.confidence = confidence
        self.visibleTime = visibleTime
        self.pinchDistance = pinchDistance
        self.grabAngle = grabAngle
        self.pinchStrength = pinchStrength
        self.grabStrength = grabStrength
        self.palm = palm
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.pinky = pinky
        self.arm = arm
        self.isPinching = isPinching
    }

    init(_ hand: LEAP_HAND) {
        // C fixed-size array [5] imports as a 5-tuple
        let d = hand.digits
        let flags = hand.flags
        self.init(
            id: hand.id,
            type: hand.type == eLeapHandType_Left ? .left : .right,
            confidence: hand.confidence,
            visibleTime: hand.visible_time,
            pinchDistance: hand.pinch_distance,
            grabAngle: hand.grab_angle,
            pinchStrength: hand.pinch_strength,
            grabStrength: hand.grab_strength,
            palm: Palm(hand.palm),
            thumb: Finger(d.0),
            index: Finger(d.1),
            middle: Finger(d.2),
            ring: Finger(d.3),
            pinky: Finger(d.4),
            arm: Bone(hand.arm),
            isPinching: (flags & UInt32(eLeapHandFlag_GesturePinch.rawValue)) != 0
        )
    }
}

// MARK: - HandFrame

/// A snapshot of all tracked hands at a single point in time.
public struct HandFrame: Sendable {
    /// The unique frame identifier.
    public let frameId: Int64
    /// The timestamp in microseconds (relative to LeapGetNow()).
    public let timestamp: Int64
    /// All hands tracked in this frame (0, 1, or 2 hands).
    public let hands: [Hand]
    /// Current tracking frame rate in hertz.
    public let frameRate: Float

    /// The left hand, if present.
    public var leftHand: Hand? { hands.first { $0.type == .left } }
    /// The right hand, if present.
    public var rightHand: Hand? { hands.first { $0.type == .right } }

    /// Designated public initializer — also used for testing and mocking.
    public init(frameId: Int64, timestamp: Int64, hands: [Hand], frameRate: Float) {
        self.frameId = frameId
        self.timestamp = timestamp
        self.hands = hands
        self.frameRate = frameRate
    }

    // Copies all pointer data immediately before the next LeapPollConnection call.
    init(_ event: LEAP_TRACKING_EVENT) {
        let hands: [Hand]
        if let pHands = event.pHands, event.nHands > 0 {
            hands = (0..<Int(event.nHands)).map { Hand(pHands[$0]) }
        } else {
            hands = []
        }
        self.init(
            frameId: event.info.frame_id,
            timestamp: event.info.timestamp,
            hands: hands,
            frameRate: event.framerate
        )
    }
}

// MARK: - Device Info

/// Information about a connected Ultraleap device.
public struct DeviceInfo: Sendable {
    public let serialNumber: String
    public let horizontalFOV: Float
    public let verticalFOV: Float
    public let range: UInt32
    public let baseline: UInt32

    init?(_ info: LEAP_DEVICE_INFO) {
        guard let serial = info.serial.map({ String(cString: $0) }) else { return nil }
        self.serialNumber = serial
        self.horizontalFOV = info.h_fov
        self.verticalFOV = info.v_fov
        self.range = info.range
        self.baseline = info.baseline
    }
}

// MARK: - LeapEvent

/// Events emitted by LeapController.
public enum LeapEvent: Sendable {
    case connected
    case disconnected
    case deviceFound(DeviceInfo?)
    case deviceLost
    case trackingFrame(HandFrame)
}
