// swift-tools-version: 6.0
import PackageDescription

// The Ultraleap SDK is not redistributable, so it is referenced in place from the
// local Ultraleap Hand Tracking installation. Override with LEAPSDK_PATH if you
// installed it somewhere else.
let leapSDK = Context.environment["LEAPSDK_PATH"]
    ?? "/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK"

let package = Package(
    name: "LeapSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LeapSwift", targets: ["LeapSwift"])
    ],
    targets: [
        // Wraps the LeapC headers, sharing the same modulemap as the Xcode
        // project. The header path inside it is absolute; if your SDK lives
        // elsewhere, edit the modulemap as well as setting LEAPSDK_PATH.
        .systemLibrary(name: "LeapC", path: "LeapSwift/LeapCBridge"),

        .target(
            name: "LeapSwift",
            dependencies: ["LeapC"],
            path: "LeapSwift",
            exclude: ["LeapCBridge"],
            resources: [
                .process("MockData")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // -L is not expressible without unsafeFlags: the SDK ships no
                // pkg-config file, so there is no supported way to hand SPM a
                // library search path. See README for what this rules out.
                .unsafeFlags([
                    "-L\(leapSDK)/lib",
                    "-Xlinker", "-rpath", "-Xlinker", "\(leapSDK)/lib"
                ]),
                .linkedLibrary("LeapC.6")
            ]
        ),

        .testTarget(
            name: "LeapSwiftTests",
            dependencies: ["LeapSwift"],
            path: "LeapSwiftTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
