import Foundation
import CrispCore

/// Drives the audio analysis behind the live cut preview: runs `AnalysisRunner`,
/// caches the result per silence floor, and handles task cancellation / late
/// completions — the same orchestration shape as the other `Services/` models, kept
/// out of the view so `PreviewSheet` only renders this state.
@MainActor
@Observable
final class PreviewModel {
    private(set) var current: VideoAnalysis?
    private(set) var isAnalyzing = false
    private(set) var errorText: String?

    /// Cache keyed by rounded silence floor (dB): switching strength presets reuses
    /// the same analysis; only a different floor needs a re-run.
    private var cache: [Int: VideoAnalysis] = [:]
    private var task: Task<Void, Never>?

    /// Load the analysis for `input` at `noiseDB`, from cache if present. Cancels any
    /// in-flight run first so a superseded, different-floor result can't land late
    /// and clobber `current`.
    func load(input: URL, noiseDB: Double) {
        let key = Int(noiseDB.rounded())
        if let cached = cache[key] {
            task?.cancel()
            isAnalyzing = false
            current = cached
            return
        }
        task?.cancel()
        isAnalyzing = true
        errorText = nil
        current = nil
        task = Task { [weak self] in
            do {
                let analysis = try await AnalysisRunner().analyze(input: input, noiseDB: noiseDB)
                guard let self, !Task.isCancelled else { return }
                cache[key] = analysis
                current = analysis
                isAnalyzing = false
            } catch is CancellationError {
                // Superseded or dismissed — leave state to the newer load.
            } catch {
                guard let self, !Task.isCancelled else { return }
                errorText = "Couldn\u{2019}t analyze this video."
                isAnalyzing = false
            }
        }
    }

    func cancel() { task?.cancel() }
}
