// swift-tools-version: 6.0
import PackageDescription

// CrispKit — the platform-free half of the cleaning engine.
//
// Every algorithm here is a pure function over values: no ffmpeg, no subprocesses,
// no AppKit, no file system beyond path arithmetic. That is deliberate. It is the
// half of `packages/engine` that can run unchanged on macOS, iOS and iPadOS, and it
// is being ported ahead of the media layer so the risky work (AVFoundation) lands
// on a core that is already proven correct.
//
// Deployment targets are the *iOS* app's, not the Mac app's, so nothing in here can
// accidentally depend on a macOS-only API.
let package = Package(
    name: "CrispKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CrispKit", targets: ["CrispKit"])
    ],
    targets: [
        .target(name: "CrispKit"),
        .testTarget(
            name: "CrispKitTests",
            dependencies: ["CrispKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
