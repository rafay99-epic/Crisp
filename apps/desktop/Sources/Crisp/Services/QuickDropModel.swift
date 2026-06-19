import Foundation
import CrispCore

/// Drives the menu-bar quick-drop: clean videos dropped on the menu-bar panel with
/// the user's default recipe, headlessly (no main window), one at a time. Mirrors
/// the watch-folder / App-Intent path by going through `QuickClean`, so the output
/// is identical to every other surface — this just adds a place to start one.
@MainActor
@Observable
final class QuickDropModel {
    enum State: Equatable {
        case idle
        case cleaning(name: String, remaining: Int)
        case done(output: URL, saved: Double)
        case failed(String)
    }

    private(set) var state: State = .idle

    private var pending: [URL] = []
    private var running = false

    var isBusy: Bool { running }

    /// Accept dropped/chosen items: keep the videos, enqueue them, and start draining
    /// if idle. Returns false if nothing was a cleanable video (so the UI can hint).
    @discardableResult
    func enqueue(_ urls: [URL], settings: EngineSettings) -> Bool {
        let videos = urls.filter { CleanRunner.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return false }
        pending.append(contentsOf: videos)
        if !running { Task { await drain(settings: settings) } }
        return true
    }

    private func drain(settings: EngineSettings) async {
        running = true
        defer { running = false }

        // "Default recipe": the default preset's strength if one is set, else Balanced;
        // fillers on (the headline feature) — QuickClean provisions the model if needed.
        let strength = settings.defaultPreset.flatMap { Strength(rawValue: $0.strength) } ?? .balanced

        var cleaned = 0, failed = 0
        var lastOutput: URL?
        var totalSaved = 0.0

        while !pending.isEmpty {
            let url = pending.removeFirst()
            state = .cleaning(name: url.lastPathComponent, remaining: pending.count)
            do {
                let result = try await QuickClean().clean(url, strength: strength, removeFillers: true)
                cleaned += 1
                totalSaved += result.savedSeconds
                if !result.output.isEmpty { lastOutput = URL(fileURLWithPath: result.output) }
            } catch is CancellationError {
                break
            } catch {
                failed += 1
                state = .failed(error.localizedDescription)
            }
        }

        if let lastOutput, cleaned > 0 {
            state = .done(output: lastOutput, saved: totalSaved)
        } else if failed == 0 {
            state = .idle
        }
        // Ping when the app isn't frontmost (the whole point of a background drop).
        if cleaned > 0 || failed > 0 {
            Notifier.batchFinished(cleaned: cleaned, savedSeconds: totalSaved, failed: failed)
        }
    }
}
