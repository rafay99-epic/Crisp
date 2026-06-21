// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Absolute path to the App Intents protocols list the Swift frontend reads via
// `-const-gather-protocols-file` to know which conformances to extract const
// values for. The frontend resolves the path against its own working directory
// (not the package root), so it must be absolute. It expects a plain JSON array
// of bare protocol names (the names mirror Xcode's shipped SwiftConstantValues
// list); build.sh then feeds the emitted `.swiftconstvalues` to
// `appintentsmetadataprocessor`.
let protocolsFile = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/AppIntents.protocols.json").path

let package = Package(
    name: "Crisp",
    platforms: [.macOS(.v15)],
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
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Emit `.swiftconstvalues` so build.sh can run
                // `appintentsmetadataprocessor` to produce the Metadata.appintents
                // bundle Shortcuts/Spotlight read (swift build doesn't do this step
                // the way Xcode does). Harmless for a plain `swift build`.
                .unsafeFlags([
                    "-Xfrontend", "-const-gather-protocols-file",
                    "-Xfrontend", protocolsFile,
                    "-emit-const-values"
                ])
            ]
        ),
        // The background watch-folder agent. A separate executable so it can run
        // as a login-item LaunchAgent even when the main window is closed; reuses
        // CrispCore for all engine/config/model work.
        .executableTarget(
            name: "CrispWatcher",
            dependencies: ["CrispCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Headless CLI invoked by the Finder "Clean with Crisp" Quick Action
        // (an Automator workflow installed into ~/Library/Services). Cleans each
        // file path it's given via the shared QuickClean path.
        .executableTarget(
            name: "CrispClean",
            dependencies: ["CrispCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The on-device filler detector the engine shells out to (CRISP_FILLER):
        // reads a WAV, computes the model's log-mel via Accelerate (BLAS DFT), and
        // runs the bundled Core ML model. Standalone — no CrispCore dependency.
        .executableTarget(
            name: "crisp-filler",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate")
            ]
        ),
        .testTarget(
            name: "CrispTests",
            dependencies: ["Crisp", "CrispCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
