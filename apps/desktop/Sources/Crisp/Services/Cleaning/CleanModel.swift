import Foundation
import SwiftUI

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

/// Drives the Python engine as a subprocess and publishes its progress/results to
/// the UI. Knows nothing about views — it spawns `clean_video.py … --ndjson` and
/// decodes the event stream into observable state.
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
        let script = try CleanEngine.scriptURL()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CleanEngine.python)
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
        if let f = CleanEngine.bundledTool("ffmpeg") { env["CRISP_FFMPEG"] = f }
        if let p = CleanEngine.bundledTool("ffprobe") { env["CRISP_FFPROBE"] = p }
        if let w = CleanEngine.bundledTool("whisper-cli") { env["CRISP_WHISPER"] = w }
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
