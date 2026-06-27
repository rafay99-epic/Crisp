import Foundation
import CrispCore

/// On-demand "pre-flight" estimate: how much the queued videos would shrink, shown
/// before committing to a clean. Reuses the same analyze pass + cut math as the live
/// preview (`AnalysisRunner` + `CutPreview`), summed across the waiting files. Pauses
/// only — fillers need transcription, so they're not counted here.
@MainActor
@Observable
final class EstimateModel {
    enum State: Equatable {
        case idle
        case estimating(done: Int, total: Int)
        /// `partial` = at least one file couldn't be analyzed.
        case done(removedSeconds: Double, origSeconds: Double, pauseCount: Int, partial: Bool)
        case failed
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isEstimating: Bool { if case .estimating = state { return true }; return false }

    /// Clear a stale estimate (the recipe or queue changed).
    func reset() {
        task?.cancel()
        state = .idle
    }

    /// Analyze each waiting file at its own resolved parameters and sum the result.
    func estimate(_ items: [(url: URL, params: CleanParameters)]) {
        task?.cancel()
        guard !items.isEmpty else { state = .idle; return }
        state = .estimating(done: 0, total: items.count)
        task = Task {
            var removed = 0.0, orig = 0.0, pauses = 0, failures = 0, done = 0
            for item in items {
                if Task.isCancelled { return }
                do {
                    let analysis = try await AnalysisRunner().analyze(input: item.url, noiseDB: item.params.noiseDB)
                    let cut = CutPreview.compute(silences: analysis.silences, duration: analysis.duration,
                                                 pause: item.params.pause, keepPause: item.params.keepPause,
                                                 minKeep: item.params.minKeep)
                    removed += cut.removedSeconds
                    orig += analysis.duration
                    pauses += cut.pauseCount
                } catch is CancellationError {
                    return
                } catch {
                    failures += 1
                }
                done += 1
                if Task.isCancelled { return }
                state = .estimating(done: done, total: items.count)
            }
            if Task.isCancelled { return }
            state = orig > 0 ? .done(removedSeconds: removed, origSeconds: orig,
                                     pauseCount: pauses, partial: failures > 0)
                             : .failed
        }
    }
}
