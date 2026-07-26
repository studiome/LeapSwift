# Getting Started

Connect to the tracking service, consume frames, and shut down cleanly.

## Overview

LeapSwift has one entry point: ``LeapController``. Creating it opens a
connection to the Ultraleap service and starts a background polling loop;
consuming ``LeapController/events`` delivers everything that loop observes.

### Create a Controller

``LeapController/init(trackingMode:)`` is `async throws`. It throws a
``LeapError`` if the connection to the service cannot be created or opened —
most often because the Ultraleap Hand Tracking service is not running.

```swift
import LeapSwift

let controller = try await LeapController(trackingMode: .desktop)
```

The tracking mode is applied once the service reports a connection, so there is
no need to wait for ``LeapEvent/connected`` before setting it. To change it
later, call ``LeapController/setTrackingMode(_:)``.

### Consume Events

``LeapController/events`` is an `AsyncStream` you can iterate from any task. The
stream carries connection lifecycle events alongside tracking frames, so a
single loop can drive both your UI state and your hand rendering.

```swift
let task = Task {
    for await event in controller.events {
        switch event {
        case .connected:
            status = "Connected"
        case .disconnected:
            status = "Service unavailable"
        case .deviceFound:
            status = "Device ready"
        case .deviceLost:
            status = "Device unplugged"
        case .trackingFrame(let frame):
            render(frame)
        case .error(let error):
            log(error.localizedDescription)
        @unknown default:
            break
        }
    }
}
```

> Note: ``LeapEvent`` is not `@frozen`, so a `switch` outside the framework needs
> an `@unknown default`. ``HandType`` and ``VersionPart`` are frozen and switch
> exhaustively without one.

Failures raised while the controller is handling an event cannot be thrown to
you, so they arrive as ``LeapEvent/error(_:)``. The controller keeps running: it
stays connected and retries opening a device on the next ``LeapEvent/connected``
or ``LeapEvent/deviceFound(_:)``.

If you only care about hand data, ``LeapController/frames`` maps the stream to
`HandFrame?`, emitting `nil` for non-tracking events:

```swift
for await frame in controller.frames {
    guard let frame else { continue }
    render(frame)
}
```

> Important: The stream is unicast. Iterating ``LeapController/events`` from two
> places splits the events between them rather than duplicating them. To fan out
> to multiple consumers, iterate once and rebroadcast.

### Detect a Gesture

Pinch and grab are reported per hand as normalized strengths, which is usually
easier to work with than raw joint positions.

```swift
for await frame in controller.frames {
    guard let hand = frame?.rightHand else { continue }

    if hand.grabStrength > 0.8 {
        beginDrag(at: hand.palm.position)
    } else if hand.pinchStrength > 0.9 {
        select(at: hand.index.tipPosition)
    }
}
```

``Hand/palm`` also exposes ``Palm/stabilizedPosition``, a time-filtered position
that is better suited to pointing at 2D UI than the raw
``Palm/position``.

> Note: ``Hand/isPinching`` reflects the service's own gesture flag, which
> requires a gesture detection license. Without one it stays `false`; compare
> ``Hand/pinchStrength`` or ``Hand/pinchDistance`` against a threshold instead.

### Inspect the Device

Device details become available once a device has been opened, which happens
automatically after ``LeapEvent/connected``. Before that,
``LeapController/deviceInfo()`` returns `nil`.

```swift
if let info = await controller.deviceInfo() {
    print("Serial: \(info.serialNumber)")
    print("FOV: \(info.horizontalFOV) × \(info.verticalFOV)")
}

let version = try await controller.version(of: .serverLibrary)
print("Service v\(version.major).\(version.minor).\(version.patch)")
```

### Shut Down

``LeapController/stop()`` cancels polling, finishes the event stream — which
ends any `for await` loop over it — and closes the device and connection.
`deinit` performs the same teardown, so stopping explicitly is only necessary
when you want tracking to end before the controller is released.

```swift
await controller.stop()
```

Calling ``LeapController/stop()`` more than once is safe. After stopping, the
controller cannot be reconnected; create a new one instead.

## See Also

- ``LeapController``
- ``LeapEvent``
- <doc:HandModel>
