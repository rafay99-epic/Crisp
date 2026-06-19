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
        case preparing(name: String)
        case cleaning(name: String, remaining: Int)
        /// A finished batch: how many succeeded (with the last output to reveal) and
        /// how many failed — so a mixed batch never hides a failure.
        case done(output: URL?, saved: Double, cleaned: Int, failed: Int)
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
        // Flip the guard synchronously (not inside the scheduled drain Task), so two
        // enqueues in the same turn can't both spawn a drain and race on `pending`.
        if !running {
            running = true
            Task { await drain(settings: settings) }
        }
        return true
    }

    private func drain(settings: EngineSettings) async {
        defer { running = false }

        // "Default recipe": the default preset's strength if one is set, else Balanced;
        // fillers on (the headline feature) — QuickClean provisions the model if needed.
        let strength = settings.defaultPreset.flatMap { Strength(rawValue: $0.strength) } ?? .balanced

        var cleaned = 0, failed = 0
        var lastOutput: URL?
        var totalSaved = 0.0

        while !pending.isEmpty {
            let url = pending.removeFirst()
            // "Preparing" until the first engine event — covers the one-time speech
            // model download, so a first-run drop doesn't look like it's hung.
            state = .preparing(name: url.lastPathComponent)
            do {
                let result = try await QuickClean().clean(url, strength: strength, removeFillers: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .preparing = self.state {
                            self.state = .cleaning(name: url.lastPathComponent, remaining: self.pending.count)
                        }
                    }
                }
                cleaned += 1
                totalSaved += result.savedSeconds
                if !result.output.isEmpty { lastOutput = URL(fileURLWithPath: result.output) }
            } catch is CancellationError {
                break
            } catch {
                failed += 1   // reflected in the final state below, not mid-loop
            }
        }

        if cleaned > 0 {
            // Mixed batches keep the failure count visible alongside the successes.
            state = .done(output: lastOutput, saved: totalSaved, cleaned: cleaned, failed: failed)
        } else if failed > 0 {
            state = .failed(failed == 1 ? "Couldn\u{2019}t clean the video."
                                        : "Couldn\u{2019}t clean \(failed) videos.")
        } else {
            state = .idle
        }
        // Ping when something was actually cleaned and the app isn't frontmost (the
        // point of a background drop). An all-failure run shows its error in the
        // panel rather than a misleading "Cleaned 0" notification.
        if cleaned > 0 {
            Notifier.batchFinished(cleaned: cleaned, savedSeconds: totalSaved, failed: failed)
        }
    }
}
