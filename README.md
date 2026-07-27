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

- macOS 13.0 or later
- Xcode 16.0 or later to build
- **Ultraleap Hyperion version 6.0 or later** — Ultraleap's v6 hand tracking
  software, v6.2.0 at the time of writing — installed at
  `/Applications/Ultraleap Hand Tracking.app`, with the tracking service
  running. Intel and Apple Silicon builds are both provided;
  [download](https://www.ultraleap.com/downloads/leap-motion-controller-2/)
- A **Leap Motion Controller 2**, the device Hyperion supports

> Important: version 6 is a hard requirement, not a recommendation. LeapSwift
> links `libLeapC.6.dylib` — the v6 series of the LeapC library. The previous
> release, **Ultraleap Gemini** (v5), ships `libLeapC.5.dylib` under a different
> install name, so the build will not link against it. Ultraleap also states
> that Hyperion needs a Leap Motion Controller 2 and does not support the
> original Leap Motion Controller, for which Gemini v5 remains the current
> software.

## Installation

Clone the repository and build the framework:

```bash
git clone https://github.com/studiome/LeapSwift.git
```

Open `LeapSwift.xcodeproj` and build the `LeapSwift` scheme, or:

```bash
xcodebuild -project LeapSwift.xcodeproj -scheme LeapSwift -destination 'platform=macOS'
```

The package also builds with Swift Package Manager, against the same sources:

```bash
swift build
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

## Using LeapSwift in an app

### Swift Package Manager

Add the package by branch, by commit, or by local path:

```swift
.package(url: "https://github.com/studiome/LeapSwift.git", branch: "main")
.package(url: "https://github.com/studiome/LeapSwift.git", revision: "<commit>")
.package(path: "../LeapSwift")
```

> Important: a **version** requirement (`from:`, `.upToNextMajor`, an exact tag)
> does not work. SPM rejects it with *"contains unsafe build flags"*, because the
> package must pass the SDK's library search path with `unsafeFlags` — the
> Ultraleap SDK ships no pkg-config file, so there is no supported alternative.
> Branch, revision, and path dependencies are unaffected.

Releases are tagged all the same, so there is a stable commit to pin to. In
Xcode's *Add Package Dependency* sheet the **Version** rules will fail for the
reason above — choose **Branch** (`main`) or **Commit**, pasting the commit a
release tag points at:

```bash
git ls-remote https://github.com/studiome/LeapSwift.git refs/tags/0.1.0
```

Set `LEAPSDK_PATH` if your SDK is not at the default location. Note that this only
covers linking; the header path lives in `LeapSwift/LeapCBridge/module.modulemap`
and has to be edited to match.

An SPM-built binary links `@rpath/libLeapC.6.dylib` and finds it through a runpath
into the installed SDK, so nothing is copied into your build.

### Xcode framework

Add `LeapSwift.xcodeproj` to your app project as a subproject, or build the
framework and add the product directly. In both cases add `LeapSwift.framework` to
your app target's *Frameworks, Libraries, and Embedded Content* with
**Embed & Sign**.

Your app needs no configuration for `libLeapC`. The framework carries its own copy
in `LeapSwift.framework/Versions/A/Frameworks` and resolves it through its own
`@loader_path/Frameworks` runpath, so the app binary only ever links
`LeapSwift.framework` itself.

### App Sandbox

A sandboxed app **must** declare the network client entitlement, because `LeapC`
reaches the tracking service over a local socket:

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
```

Without `com.apple.security.network.client` the failure is silent and easy to
misdiagnose: `LeapController()` still succeeds, but the connection is never
established and no `connected` event ever arrives. No error is thrown.

> Important: `LeapController()` returning does not mean you are connected — it
> only means the connection was opened locally. Always treat the `connected`
> event as the signal that the service is actually reachable.

### Handling failures

Errors from calls you make are thrown. Failures that happen while the controller
is processing an event have nowhere to be thrown to, so they arrive on the stream
as `LeapEvent.error`:

```swift
case .error(let error):
    log("tracking problem: \(error.localizedDescription)")
```

The controller keeps running after reporting one — it stays connected and retries
opening a device on the next `connected` or `deviceFound`.

### Swift 6 language mode

The framework is built with library evolution, so a public enum is only
exhaustively switchable from outside if it is `@frozen`:

| Enum | Frozen | Needs `@unknown default` |
| ---- | ------ | ------------------------ |
| `HandType` | yes | no |
| `VersionPart` | yes | no |
| `LeapEvent` | no | **yes** |
| `LeapError` | no | **yes** |
| `TrackingMode` | no | **yes** |

`HandType` and `VersionPart` describe closed sets, so they are frozen and switch
exhaustively. The other three are expected to gain cases — `LeapEvent` and
`LeapError` grow as more conditions are reported, and `TrackingMode` follows
Ultraleap's modes — so they stay non-frozen and require `@unknown default`.
Omitting it is a warning in Swift 5 and an error in Swift 6.

## Mock mode

Hand tracking normally requires the Ultraleap service and a physical device.
LeapSwift can also stream synthetic hand data instead, so you can build and
demo UI and gesture logic without either:

```swift
let controller = try await LeapController(mock: .always)
for await event in controller.events {
    // Exactly the same events a real device would send.
}
```

**Mocking is opt-in and off by default.** `LeapController()` with no `mock`
argument talks to real LeapC exactly as it always has — a release build can
never start streaming fake frames unless something explicitly asks for it.
`mock` defaults to `MockPolicy.resolved()`, which checks, in order:

1. The `-LeapSwiftMock` launch argument (handy from an Xcode scheme).
2. The `LEAPSWIFT_MOCK` environment variable.
3. `MockPolicy.disabled`, if neither is set or recognized.

Both accept the same values: `off`/`disabled`/`0`, `auto`/`whenNoDevice`, and
`always`/`on`/`1`. Or pass a `MockPolicy` directly:

| Policy | Behavior |
| ------ | -------- |
| `.disabled` | Real LeapC only. The default. |
| `.always` | Mock only. LeapC is never touched. |
| `.whenNoDevice` | Tries the real device; falls back to the mock if the connection fails, no device is found, or a device stops producing frames. Switches back automatically if a real device starts working. |

`mockScenario` picks what the mock streams: `.noHands`, `.idleRightHand`,
`.bothHandsIdle`, `.openClose`, `.pinch`, or `.wave`. All of `LeapController`'s
API works the same while mocked — `deviceInfo()` returns a pseudo device,
`version(of:)` returns a placeholder version, and `setTrackingMode`/
`setBackgroundFrames` succeed without doing anything, rather than throwing as
they would with no real connection.

For lower-level control, `MockLeapServer` and `MockHandFactory` are public —
useful for driving a preview or a test directly, without going through
`LeapController` at all:

```swift
let server = MockLeapServer(scenario: .pinch)
await server.start()
for await event in server.events { ... }
```

`MockRecording` reads and writes the same data as a JSON file, so you can
replay a captured or hand-authored session:

```swift
let recording = try MockRecording.bundled(.wave)   // ships with LeapSwift
await server.play(recording, loop: true)
```

The *Mock Mode* article in the DocC catalog has the full picture, including how
to record and load your own sessions.

## Tests

```bash
xcodebuild test -project LeapSwift.xcodeproj -scheme LeapSwift -destination 'platform=macOS'
swift test
```

The suite covers the value types and geometry helpers. It needs no device and no
running tracking service, but the machine must still have Ultraleap Hand Tracking
installed, because building the framework requires the `LeapC` headers and
library. Hosted CI runners without that installation cannot build the project.

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

LeapSwift is available under the MIT licence. See [LICENSE](LICENSE), and
[NOTICE](NOTICE) for what that licence does and does not cover.

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
