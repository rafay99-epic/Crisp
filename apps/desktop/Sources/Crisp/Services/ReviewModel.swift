import AVFoundation
import SwiftUI
import CrispCore

/// Drives the review timeline: plays the *source* video, analyzes its pauses once
/// (reusing the engine's analyze-only mode via `AnalysisRunner`), and exposes the
/// detected cuts as toggleable `CutRegion`s. The user flips individual cuts on/off
/// and can preview the result (playback skips the enabled cuts), then clean to the
/// exact keep-list. Pure cut/keep math lives in `CutPreview`; this owns the player,
/// the analysis lifecycle, and the playhead — the view only renders.
@MainActor
@Observable
final class ReviewModel {
    private(set) var duration: Double = 0
    /// The detected cuts, in order; `enabled` means the stretch will be removed.
    var cuts: [CutPreview.CutRegion] = []
    private(set) var isLoading = false
    private(set) var errorText: String?
    /// Playhead position in seconds, published from the player's periodic observer.
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    /// When on, playback skips over the enabled cuts so the user hears/sees the
    /// result without rendering.
    var previewResult = false

    let player = AVPlayer()
    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var analysisTask: Task<Void, Never>?

    // MARK: - Derived

    /// The keep-list the engine will render (`[0, duration]` minus the enabled cuts).
    var keep: [ClosedRange<Double>] { CutPreview.keep(forCuts: cuts, duration: duration) }
    var keptSeconds: Double { keep.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } }
    var removedSeconds: Double { max(0, duration - keptSeconds) }
    var enabledCutCount: Int { cuts.filter(\.enabled).count }
    /// Whether anything would actually be cut (guards the Clean action).
    var hasCuts: Bool { enabledCutCount > 0 }

    // MARK: - Lifecycle

    /// Load the source into the player and kick off the one-time pause analysis at the
    /// recipe's silence floor + cut knobs, so the initial cuts match what a normal
    /// clean would do.
    func load(url: URL, params: CleanParameters) {
        let item = AVPlayerItem(url: url)
        self.item = item
        player.replaceCurrentItem(with: item)
        addObservers()

        isLoading = true
        errorText = nil
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            do {
                let analysis = try await AnalysisRunner().analyze(input: url, noiseDB: params.noiseDB)
                guard let self, !Task.isCancelled else { return }
                self.duration = analysis.duration
                let initialKeep = CutPreview.compute(
                    silences: analysis.silences, duration: analysis.duration,
                    pause: params.pause, keepPause: params.keepPause, minKeep: params.minKeep,
                    pauseMode: params.pauseMode, tightPause: params.tightPause).keep
                self.cuts = CutPreview.cutRegions(keep: initialKeep, duration: analysis.duration)
                self.isLoading = false
            } catch is CancellationError {
                // Superseded or dismissed.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorText = "Couldn\u{2019}t analyze this video."
                self.isLoading = false
            }
        }
    }

    func stop() {
        player.pause()
        isPlaying = false
        analysisTask?.cancel()
        removeObservers()
        player.replaceCurrentItem(with: nil)
        item = nil
    }

    // MARK: - Editing

    func toggleCut(_ id: Int) {
        guard let idx = cuts.firstIndex(where: { $0.id == id }) else { return }
        cuts[idx].enabled.toggle()
    }

    func enableAllCuts(_ enabled: Bool) {
        for i in cuts.indices { cuts[i].enabled = enabled }
    }

    // MARK: - Transport

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Restarting from the very end would stick; nudge back to start.
            if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    /// Seek frame-accurately (zero tolerance) so the playhead lands exactly where the
    /// user asked — essential for trusting a cut boundary.
    func seek(to seconds: Double) {
        let clamped = max(0, min(duration > 0 ? duration : seconds, seconds))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Observers

    private func addObservers() {
        removeObservers()
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // The observer fires on the main queue; hop to the actor to touch state.
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = time.seconds
                guard t.isFinite else { return }
                self.currentTime = t
                // Preview mode: when the playhead enters an enabled cut, jump to its
                // end so the user experiences the cleaned result.
                if self.previewResult, self.isPlaying,
                   let cut = self.cuts.first(where: { $0.enabled && t >= $0.start && t < $0.end - 0.04 }) {
                    self.seek(to: cut.end)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.seek(to: 0)
            }
        }
    }

    private func removeObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
