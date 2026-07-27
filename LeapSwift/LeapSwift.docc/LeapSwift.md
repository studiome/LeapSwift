# ``LeapSwift``

Track hands in three dimensions with Ultraleap hardware, using a Swift-native
async/await API.

## Overview

LeapSwift wraps the Ultraleap `LeapC` tracking service in Swift value types and
structured concurrency. A single ``LeapController`` owns the connection to the
tracking service and publishes everything it observes — connection changes,
device arrival, and per-frame hand data — as an `AsyncStream` of ``LeapEvent``.

```swift
import LeapSwift

let controller = try await LeapController()
for await event in controller.events {
    switch event {
    case .connected:
        print("Connected to the Ultraleap service")
    case .trackingFrame(let frame):
        if let left = frame.leftHand {
            print("Left palm: \(left.palm.position)")
        }
    default:
        break
    }
}
```

Every type that crosses the stream — ``HandFrame``, ``Hand``, ``Finger``,
``Bone``, ``Palm`` — is a `Sendable` value type. The controller copies all data
out of the C tracking buffers before the next poll, so a frame you hold onto
stays valid indefinitely and can be passed freely between tasks and actors.

### Requirements

LeapSwift links against `libLeapC` from the Ultraleap Hand Tracking
installation and requires the tracking service to be running:

- macOS 13.0 or later, on Apple Silicon
- **Ultraleap Hand Tracking** installed at
  `/Applications/Ultraleap Hand Tracking.app`
- A connected Ultraleap device (Leap Motion Controller, Controller 2, or Stereo IR 170)

### Coordinate System

All positions are in **millimeters**, relative to the center of the device.
Orientations are unit quaternions (``Quaternion``) in the same space.

| Axis | Positive direction |
| ---- | ------------------ |
| X    | Toward the user's right |
| Y    | Upward, away from the device |
| Z    | Toward the user |

The origin depends on the active ``TrackingMode``: with ``TrackingMode/desktop``
the device faces up from a flat surface, while ``TrackingMode/headMounted``
assumes the device is mounted on a headset and looking outward.

### Reading a Frame

A ``HandFrame`` carries zero, one, or two hands. Rather than indexing into
``HandFrame/hands``, prefer the ``HandFrame/leftHand`` and
``HandFrame/rightHand`` accessors — hand order is not guaranteed to be stable
between frames, whereas ``Hand/id`` and ``Hand/type`` are.

```swift
for await event in controller.events {
    guard case .trackingFrame(let frame) = event,
          let hand = frame.rightHand else { continue }

    if hand.pinchStrength > 0.9 {
        print("Pinch at \(hand.index.tipPosition)")
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``LeapController``
- ``LeapEvent``

### Hand Data

- <doc:HandModel>
- ``HandFrame``
- ``Hand``
- ``HandType``
- ``Palm``
- ``Finger``
- ``Bone``

### Configuration

- ``TrackingMode``
- ``LeapController/setTrackingMode(_:)``
- ``LeapController/setBackgroundFrames(enabled:)``

### Device and Version Information

- ``DeviceInfo``
- ``LeapController/deviceInfo()``
- ``VersionPart``
- ``LeapController/version(of:)``
- ``frameworkVersion``

### Mocking

- <doc:MockMode>
- ``MockPolicy``
- ``MockScenario``
- ``MockLeapServer``
- ``MockHandFactory``
- ``MockRecording``

### Geometry

- ``Vector3``
- ``Quaternion``

### Errors

- ``LeapError``
