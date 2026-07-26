# LeapSwift

A Swift framework for hand tracking on macOS, wrapping the Ultraleap `LeapC` API
in value types and structured concurrency.

Hand tracking itself is provided by **Ultraleap Hand Tracking** and Ultraleap
hardware. LeapSwift performs no tracking of its own — it is a thin Swift binding
over Ultraleap's tracking service.

```swift
import LeapSwift

let controller = try await LeapController()
for await event in controller.events {
    if case .trackingFrame(let frame) = event,
       let hand = frame.rightHand {
        print("Palm: \(hand.palm.position), pinch: \(hand.pinchStrength)")
    }
}
```

## Features

- `AsyncStream`-based event delivery — no delegates, no callbacks
- `Sendable` value types throughout, safe to pass across tasks and actors
- Tracking data copied out of the C buffers before the next poll, so frames stay
  valid for as long as you hold them
- `simd` vectors and quaternions rather than bespoke math types
- Full DocC documentation with articles

## Requirements

- macOS 26.0 or later
- Xcode 26 or later
- **Ultraleap Hand Tracking** installed at
  `/Applications/Ultraleap Hand Tracking.app`
  ([download](https://developer.leapmotion.com/get-started/)), with the tracking
  service running
- An Ultraleap device: Leap Motion Controller, Leap Motion Controller 2, or
  Stereo IR 170

## Installation

Clone the repository and build the framework:

```bash
git clone https://github.com/<your-account>/LeapSwift.git
```

Open `LeapSwift.xcodeproj` and build the `LeapSwift` scheme, or:

```bash
xcodebuild -project LeapSwift.xcodeproj -scheme LeapSwift -destination 'platform=macOS'
```

**This repository does not bundle `libLeapC`.** The Ultraleap library and headers
are proprietary and cannot be redistributed here, so the project references them
in place from your local Ultraleap installation:

| What | Where the build looks |
| ---- | --------------------- |
| `LeapC.h` | `/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK/include` |
| `libLeapC.6.dylib` | `/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK/lib` |

If you installed Ultraleap Hand Tracking somewhere else, update
`HEADER_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` in the build settings, and the
header path in `LeapSwift/LeapCBridge/module.modulemap`, to match.

`libLeapC.6.dylib` is copied into the built framework's `Frameworks` directory by
the *Embed Libraries* build phase, so the framework you produce locally is
self-contained at runtime.

## Documentation

Build the DocC documentation in Xcode with **Product → Build Documentation**, or:

```bash
xcodebuild docbuild -project LeapSwift.xcodeproj -scheme LeapSwift -destination 'platform=macOS'
```

The catalog includes a *Getting Started* guide and an article on the hand model
(the frame → hand → finger → bone hierarchy), alongside the full API reference.

## Coordinate System

Positions are in millimeters relative to the device center. X is positive toward
the user's right, Y positive upward, and Z positive toward the user.

## Licence

LeapSwift is available under the MIT licence. See [LICENSE](LICENSE).

The MIT licence covers **only the Swift source code in this repository**. It does
not cover the Ultraleap Tracking SDK, the Ultraleap Hand Tracking Software, or
`libLeapC`, none of which are redistributed here. Those are proprietary works of
Ultraleap Limited and are licensed separately under the Ultraleap Enterprise
Licence, included with your Ultraleap installation at
`/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK/LICENSE.md`.

By installing and using the Ultraleap SDK you accept that agreement directly with
Ultraleap. LeapSwift grants you no rights to it, and using LeapSwift does not
change your obligations under it. Some points to be aware of, which are yours to
comply with and not exhaustive — read the agreement itself:

- Redistributing `libLeapC` is permitted only as packaged with your own
  application, and never as a standalone file or in a source repository.
- Applications using Ultraleap technology must attribute Ultraleap.
- The agreement prohibits use in certain fields, including weapons, gambling, and
  nuclear energy, and prohibits high-risk uses where failure could cause death,
  injury, or severe property or environmental damage.

## Acknowledgements

Hand tracking technology by [Ultraleap](https://www.ultraleap.com/).
Ultraleap, Leap Motion, and related marks are trademarks of Ultraleap Limited.
This project is not affiliated with or endorsed by Ultraleap.
