# The Hand Model

How LeapSwift represents a tracked hand, from the frame down to individual bones.

## Overview

Tracking data arrives as a nested hierarchy of value types. Each level narrows
the scope: a frame holds hands, a hand holds a palm and five fingers, and each
finger holds four bones.

```
HandFrame
├── frameId, timestamp, frameRate
└── hands: [Hand]                    // 0, 1, or 2
    ├── id, type, confidence, visibleTime
    ├── pinchStrength, pinchDistance
    ├── grabStrength, grabAngle
    ├── palm: Palm                   // position, normal, direction, orientation
    ├── arm: Bone                    // forearm
    └── thumb, index, middle, ring, pinky: Finger
        ├── id, isExtended
        └── metacarpal, proximal, intermediate, distal: Bone
            └── previousJoint, nextJoint, width, rotation
```

### Frames

``HandFrame/frameId`` increases monotonically while a connection is open, and
``HandFrame/timestamp`` is in microseconds on the service's clock — the same
timebase as `LeapGetNow()`. Use the timestamp rather than your own wall clock
when interpolating between frames or measuring velocity yourself.

``HandFrame/frameRate`` reports the service's current tracking rate in hertz,
which varies with device model, USB bandwidth, and system load.

### Hands

``Hand/id`` is stable for as long as the hand remains tracked. If the hand
leaves the field of view and returns, it comes back with a new id — so treat a
change in id as a new hand, not a continuation.

``Hand/visibleTime`` accumulates in microseconds for the life of that id, which
makes it a convenient way to ignore hands that have only just appeared and may
still be settling:

```swift
guard hand.visibleTime > 200_000 else { continue }  // tracked > 200 ms
```

``Hand/fingers`` returns the five fingers in a fixed order — thumb, index,
middle, ring, pinky — matching the named properties. Iterate it when you want
uniform treatment, and use the named properties otherwise.

### The Palm

``Palm`` describes the hand's overall pose. Two vectors define its facing:
``Palm/normal`` points out through the palm surface, and ``Palm/direction``
points from the palm toward the fingers. Together with ``Palm/orientation`` they
give you a full frame of reference.

```swift
// Is the hand facing up (palm toward the ceiling)?
let facingUp = simd_dot(hand.palm.normal, SIMD3<Float>(0, 1, 0)) > 0.8
```

``Palm/position`` is the raw center of the palm; ``Palm/stabilizedPosition`` is a
time-filtered variant that trades a little latency for much less jitter. Prefer
the stabilized position for cursors and UI hit-testing, and the raw position for
physical simulation.

### Fingers and Bones

Each ``Finger`` exposes its four bones from the wrist outward, and
``Finger/bones`` returns them in that order.

``Finger/tipPosition`` is a shortcut for the distal bone's
``Bone/nextJoint`` — the fingertip.

> Note: In the Ultraleap skeletal model the thumb has no true metacarpal bone.
> ``Finger/metacarpal`` is still present for the thumb, but it is zero-length,
> so ``Bone/length`` returns `0` and ``Bone/center`` coincides with both joints.
> Skip it when drawing, or you will render a degenerate segment.

A ``Bone`` is a segment between two joints: ``Bone/previousJoint`` toward the
wrist, ``Bone/nextJoint`` toward the fingertip. ``Bone/center`` and
``Bone/length`` are derived from those, and ``Bone/width`` estimates the flesh
around the bone in millimeters — enough to size a capsule mesh.

```swift
for finger in hand.fingers {
    for bone in finger.bones where bone.length > 0 {
        drawCapsule(from: bone.previousJoint,
                    to: bone.nextJoint,
                    radius: bone.width * 0.5,
                    rotation: bone.rotation)
    }
}
```

``Finger/isExtended`` reports whether the finger is roughly straight, which is
the simplest basis for counting fingers or recognizing static poses:

```swift
let extended = hand.fingers.filter(\.isExtended).count
```

## See Also

- ``HandFrame``
- ``Hand``
- ``Finger``
- ``Bone``
- ``Palm``
