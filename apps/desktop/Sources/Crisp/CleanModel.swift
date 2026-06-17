import Foundation
import SwiftUI

// MARK: - Options

/// How aggressively to cut. Each preset maps to the engine's pause threshold and
/// the breathing room kept around every cut.
enum Strength: String, CaseIterable, Identifiable {
    case gentle = "Gentle"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
    case veryAggressive = "Very aggressive"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .gentle:         return "Cuts only clearly long pauses. Most natural."
        case .balanced:       return "A safe middle ground."
        case .aggressive:     return "Cuts short \u{201C}thinking\u{201D} gaps too. Recommended."
        case .veryAggressive: return "Tightest possible. Can feel fast-paced."
        }
    }
    var pause: Double {
        switch self {
        case .gentle: return 0.80
        case .balanced: return 0.60
        case .aggressive: return 0.35
        case .veryAggressive: return 0.25
        }
    }
    var keepPause: Double {
        switch self {
        case .gentle: return 0.18
        case .balanced: return 0.15
        case .aggressive: return 0.10
        case .veryAggressive: return 0.08
        }
    }
}

struct CleanResult: Identifiable {
    let id = UUID()
    let output: String
    let origSeconds: Double
    let newSeconds: Double
    let savedSeconds: Double
    let pauses: Int
    let fillers: Int
}

/// One line of the engine's `--ndjson` output.
private struct Event: Decodable {
    let event: String
    var message: String?
    var fraction: Double?
    var label: String?
    var output: String?
    var orig_seconds: Double?
    var new_seconds: Double?
    var saved_seconds: Double?
    var pauses: Int?
    var fillers: Int?
}

func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Locates the bundled Python engine + interpreter. The engine ships inside the
/// app at `Contents/Resources/engine/` (build.sh copies it there).
enum Engine {
    struct NotFound: LocalizedError {
        var errorDescription: String? {
            "The cleaning engine wasn't found inside the app. Rebuild with ./build.sh."
        }
    }

    /// `clean_video.py` inside the app bundle (or the source tree during dev).
    static func scriptURL() throws -> URL {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("engine/clean_video.py")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        throw NotFound()
    }

    /// Directory of binaries vendored into the app by `build.sh`
    /// (`engine/bin/ffmpeg`, `…/ffprobe`, `…/whisper-cli`, `…/python/…`). Absent
    /// in a plain `swift run`, in which case the engine falls back to PATH.
    static var binDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("engine/bin", isDirectory: true)
    }

    /// Absolute path to a bundled tool if it shipped and is executable, else nil
    /// — nil lets the engine resolve the tool from PATH (a dev's Homebrew install).
    static func bundledTool(_ name: String) -> String? {
        guard let p = binDir?.appendingPathComponent(name).path,
              FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    /// python3 — prefer the bundled standalone runtime, then Homebrew, then system.
    static var python: String {
        if let p = binDir?.appendingPathComponent("python/bin/python3").path,
           FileManager.default.isExecutableFile(atPath: p) { return p }
        for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/usr/bin/python3"
    }
}

// MARK: - View model

@MainActor
@Observable
final class CleanModel {
    var files: [URL] = []
    var strength: Strength = .aggressive
    var removeFillers = true

    var isRunning = false
    var progress: Double = 0
    var status = "Choose a video to begin."
    var logLines: [String] = []
    var results: [CleanResult] = []
    var errorMessage: String?

    private static let videoExtensions: Set<String> =
        ["mov", "mp4", "mkv", "m4v", "avi", "webm", "flv"]

    func addFiles(_ urls: [URL]) {
        let videos = urls.filter { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return }
        files = videos
        results = []
        errorMessage = nil
        progress = 0
        logLines = []
        status = files.count == 1
            ? "Ready: \(files[0].lastPathComponent)"
            : "Ready: \(files.count) videos"
    }

    func reset() {
        files = []
        results = []
        errorMessage = nil
        progress = 0
        logLines = []
        status = "Choose a video to begin."
    }

    /// `modelPath` is the verified whisper model from `ModelStore` (nil when the
    /// user turned fillers off — pauses-only needs no model).
    func start(modelPath: String?) async {
        guard !files.isEmpty, !isRunning else { return }
        isRunning = true
        results = []
        errorMessage = nil
        logLines = []
        progress = 0

        let total = Double(files.count)
        for (idx, url) in files.enumerated() {
            let base = Double(idx) / total
            let span = 1.0 / total
            if files.count > 1 {
                logLines.append("\u{2014} Video \(idx + 1) of \(files.count): \(url.lastPathComponent)")
            }
            do {
                try await runOne(url, base: base, span: span, modelPath: modelPath)
            } catch {
                errorMessage = error.localizedDescription
                status = "Something went wrong."
                break
            }
        }

        isRunning = false
        if errorMessage == nil {
            progress = 1
            status = "Done! Saved next to your original."
        }
    }

    private func runOne(_ url: URL, base: Double, span: Double, modelPath: String?) async throws {
        let script = try Engine.scriptURL()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Engine.python)
        var args = [
            script.path, url.path,
            "--pause", String(strength.pause),
            "--keep-pause", String(strength.keepPause),
            "--ndjson"
        ]
        if removeFillers, let model = modelPath { args += ["--model", model] }
        if !removeFillers { args.append("--no-fillers") }
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        // Point the engine at the binaries we ship; each falls back to PATH if it
        // wasn't bundled (e.g. a plain `swift run` on a dev machine).
        if let f = Engine.bundledTool("ffmpeg") { env["CRISP_FFMPEG"] = f }
        if let p = Engine.bundledTool("ffprobe") { env["CRISP_FFPROBE"] = p }
        if let w = Engine.bundledTool("whisper-cli") { env["CRISP_WHISPER"] = w }
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        try proc.run()

        let decoder = JSONDecoder()
        for try await line in outPipe.fileHandleForReading.bytes.lines {
            guard let data = line.data(using: .utf8),
                  let ev = try? decoder.decode(Event.self, from: data) else { continue }
            switch ev.event {
            case "log":
                if let m = ev.message { logLines.append(m) }
            case "progress":
                if let f = ev.fraction { progress = base + span * f }
                if let l = ev.label, !l.isEmpty { status = l }
            case "result":
                results.append(CleanResult(
                    output: ev.output ?? "",
                    origSeconds: ev.orig_seconds ?? 0,
                    newSeconds: ev.new_seconds ?? 0,
                    savedSeconds: ev.saved_seconds ?? 0,
                    pauses: ev.pauses ?? 0,
                    fillers: ev.fillers ?? 0))
            case "error":
                throw NSError(domain: "Crisp", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: ev.message ?? "Unknown error"])
            default:
                break
            }
        }
        proc.waitUntilExit()
    }
}
