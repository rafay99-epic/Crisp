// swift-tools-version:5.9
import PackageDescription

// A small, native dashboard for evaluating the filler classifier — a dev tool,
// not part of the shipped Crisp app. It drives `filler_classifier.report` (Python)
// and renders the scores in Crisp's design language.
let package = Package(
    name: "FillerBench",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FillerBench", path: "Sources/FillerBench")
    ]
)
