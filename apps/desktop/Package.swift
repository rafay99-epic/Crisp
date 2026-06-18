// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crisp",
    platforms: [.macOS(.v14)],
    targets: [
        // Engine-driving + config + model code shared by the app and the
        // background watch-folder agent (CrispWatcher). "One system, not two" —
        // the helper reuses this, never a copy.
        .target(
            name: "CrispCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Crisp",
            dependencies: ["CrispCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CrispTests",
            dependencies: ["Crisp", "CrispCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
