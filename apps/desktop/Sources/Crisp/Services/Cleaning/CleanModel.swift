import Foundation
import SwiftUI
import CrispCore

/// Drives the cleaning of the user's queued videos and publishes per-file progress
/// and results to the UI. The actual subprocess work lives in `CrispCore.CleanRunner`
/// (shared with the Finder Service, the App Intent, and the watch-folder agent);
/// this type owns the queue, the multi-file loop, the observable state the views
/// bind to, and cancellation.
@MainActor
@Observable
final class CleanModel {
    /// The clean queue, built one file at a time. Order is process order; the user
    /// reorders the waiting tail to choose what runs first.
    var queue: [QueueItem] = []
    var strength: Strength = .aggressive
    var removeFillers = true
    /// Remove repeated takes — a phrase you flubbed and immediately said again. Needs
    /// the whisper transcript, so it's skipped when the fast on-device filler
    /// classifier is the active backend (see `start`).
    var removeRetakes = true
    /// The preset stamped onto newly added files (the user's "default for new
    /// files"); kept in sync with settings by the view. `nil` ⇒ new files use the
    /// live global strength.
    var newItemPresetID: UUID?

    var isRunning = false
    var status = "Choose a video to begin."
    /// A batch-level error (e.g. the speech model couldn't be fetched). Per-file
    /// failures live on the individual `QueueItem`, not here.
    var errorMessage: String?

    /// The cleaned outputs so far — derived from the queue, so the result card and
    /// callers see finished files without a parallel array to keep in sync.
    var results: [CleanResult] { queue.compactMap(\.result) }

    /// Status tallies, derived once here so the views don't each re-filter the queue.
    var waitingCount: Int { queue.lazy.filter { $0.isWaiting }.count }
    var doneCount: Int { queue.lazy.filter { $0.status == .done }.count }

    /// Aggregate progress across the whole queue: terminal items count as done,
    /// the running ones contribute their fraction, waiting ones contribute nothing.
    var overallProgress: Double {
        guard !queue.isEmpty else { return 0 }
        let sum = queue.reduce(0.0) { acc, item in
            switch item.status {
            case .done, .failed, .cancelled: return acc + 1
            case .running:                   return acc + item.progress
            case .waiting:                   return acc
            }
        }
        return sum / Double(queue.count)
    }

    /// The in-flight run, so `cancel()` can stop it mid-batch (cancelling the task
    /// terminates the engine subprocess via `CleanRunner`'s cancellation handler).
    private var runTask: Task<Void, Never>?
    private var cancelled = false
    /// A model download in flight (only during an auto-provisioning start), so
    /// `cancel()` can stop it before the clean loop even begins.
    private var activeProvisioner: ModelProvisioner?

    // MARK: - Queue editing

    /// Append newly chosen videos to the queue (deduped against what's already
    /// queued), so files accumulate one at a time instead of replacing the batch.
    func addFiles(_ urls: [URL]) {
        let videos = urls.filter { CleanRunner.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return }
        var existing = Set(queue.map { $0.url.standardizedFileURL })
        let fresh = videos.filter { existing.insert($0.standardizedFileURL).inserted }
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh.map { QueueItem(url: $0, presetID: newItemPresetID) })
        errorMessage = nil
        updateIdleStatus()
    }

    /// Drop a row from the queue — anything except the one currently being cleaned.
    func remove(_ id: QueueItem.ID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }), queue[idx].status != .running else { return }
        queue.remove(at: idx)
        if !isRunning { updateIdleStatus() }
    }

    /// Put a failed/canceled file back to waiting so the next Clean picks it up.
    func retry(_ id: QueueItem.ID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }),
              queue[idx].status == .failed || queue[idx].status == .cancelled else { return }
        queue[idx].status = .waiting
        queue[idx].error = nil
        queue[idx].progress = 0
        queue[idx].result = nil
        if !isRunning { updateIdleStatus() }
    }

    /// Queue a fresh pass over an already-cleaned file's original — e.g. to redo it
    /// with a different preset. The finished row stays; a new waiting row is added.
    func reclean(_ id: QueueItem.ID) {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        queue.append(QueueItem(url: item.url, presetID: item.presetID))
        if !isRunning { updateIdleStatus() }
    }

    /// Reorder among the waiting tail only — you can't reorder something that's
    /// already running or finished. Destination is clamped into the waiting region.
    func moveWaiting(fromOffsets: IndexSet, toOffset: Int) {
        guard fromOffsets.allSatisfy({ queue[$0].isWaiting }) else { return }
        let firstWaiting = queue.firstIndex(where: { $0.isWaiting }) ?? queue.count
        queue.move(fromOffsets: fromOffsets, toOffset: max(toOffset, firstWaiting))
    }

    func reset() {
        guard !isRunning else { return }
        queue = []
        errorMessage = nil
        status = "Choose a video to begin."
    }

    // MARK: - Running

    /// `modelPath` is the verified whisper model from `ModelStore` (nil when the
    /// user turned fillers off — pauses-only needs no model). `resolveParameters`
    /// maps each queued file to its recipe (a per-file preset, or the window's
    /// default); it's called up front on the main actor so the run only carries
    /// plain `Sendable` values. `concurrency` is how many files to clean at once
    /// (1 = serial; the resource governor supplies a larger number).
    ///
    /// `provisioner` is used only by external triggers (the Finder Service) that
    /// may run before the model is downloaded: when fillers are on and no
    /// `modelPath` is given, the model is fetched first (progress shown in the
    /// window). The normal in-app path passes a ready `modelPath` and no
    /// provisioner, so this step is skipped.
    /// Filler-model id to record anonymous feedback under for this batch, or nil to
    /// record nothing (the opt-in is off). Frozen for the whole run in `start`.
    private var activeFeedbackModelID: String?
    /// Resolved filler-model path for this batch (coreml backend), or nil for whisper.
    /// Frozen in `start` so it doesn't need threading through drain/runOne/cleanOne.
    private var activeFillerModelPath: String?

    func start(modelPath: String?,
               fillerModelPath: String? = nil,
               feedbackModelID: String? = nil,
               concurrency: Int = 1,
               resolveParameters: (QueueItem) -> CleanParameters,
               provisioner: ModelProvisioner? = nil) async {
        let waiting = queue.filter { $0.status == .waiting }
        guard !waiting.isEmpty, !isRunning else { return }
        guard ensureLicenseAllowsClean() else { return }
        isRunning = true
        cancelled = false
        errorMessage = nil

        // Freeze the recipe for the whole run: the per-file parameters and the
        // filler/model choice are all snapshotted now, so flipping a control
        // afterward can't change files that are already in flight.
        let fillers = removeFillers
        let fillerModel = fillers ? fillerModelPath : nil   // coreml backend when present
        // Retakes need a whisper transcript, which the fast on-device classifier can't
        // produce. Rather than silently override the user's model choice, retake removal
        // is unavailable while the classifier is the active backend (the UI disables the
        // toggle the same way captions are — see ContentView/BottomBar). So it only runs
        // when the classifier isn't doing the fillers.
        let retakes = removeRetakes && fillerModel == nil
        activeFillerModelPath = fillerModel
        activeFeedbackModelID = fillerModel != nil ? feedbackModelID : nil   // record only classifier cleans
        // Record the filler backend up front, so the log says which model this clean used.
        let cleanLog = AppInfo.logger("clean")
        cleanLog.info("retake removal: \(retakes ? "on" : "off", privacy: .public)")
        if !fillers {
            cleanLog.info("filler removal: off")
        } else if let fm = fillerModel {
            cleanLog.info("filler backend: on-device model @ \(fm, privacy: .public)")
        } else {
            cleanLog.info("filler backend: whisper @ \(modelPath ?? "(none)", privacy: .public)")
        }
        var params: [QueueItem.ID: CleanParameters] = [:]
        for item in waiting { params[item.id] = resolveParameters(item) }
        let waitingIDs = waiting.map(\.id)

        var resolvedModel = modelPath
        // Provision the speech model only when whisper will actually run: retake removal
        // always needs it, and filler removal needs it unless the Core ML classifier is
        // doing the fillers (fillerModel != nil). A classifier-only run needs no whisper.
        if retakes || (fillers && fillerModel == nil), resolvedModel == nil, let provisioner {
            guard let m = await provisionModel(provisioner) else { return }
            resolvedModel = m
        }

        let recipe = Recipe(modelPath: resolvedModel, removeFillers: fillers, removeRetakes: retakes)
        let lanes = max(1, concurrency)
        let work = Task { @MainActor in
            await self.drain(waitingIDs: waitingIDs, params: params, recipe: recipe, lanes: lanes)
        }
        runTask = work
        await work.value
        runTask = nil

        isRunning = false
        finishStatus()
    }

    /// Run the queued files through up to `lanes` concurrent cleans, refilling a
    /// lane as soon as one finishes (so overflow files start automatically). With
    /// `lanes == 1` this is a plain serial pass.
    private func drain(waitingIDs: [QueueItem.ID], params: [QueueItem.ID: CleanParameters],
                       recipe: Recipe, lanes: Int) async {
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func startNext() -> Bool {
                while next < waitingIDs.count {
                    let id = waitingIDs[next]
                    next += 1
                    guard let p = params[id] else { continue }
                    group.addTask { @MainActor in
                        await self.runOne(id: id, recipe: recipe, parameters: p)
                    }
                    return true
                }
                return false
            }
            var active = 0
            for _ in 0..<lanes where startNext() { active += 1 }
            while active > 0 {
                await group.next()
                active -= 1
                if !cancelled, startNext() { active += 1 }
            }
        }
    }

    /// Stop the in-progress batch. The originals are never modified, so canceling is
    /// always safe; the running file's partial output may be left beside it, and the
    /// still-waiting items stay queued so the user can resume with Clean.
    func cancel() {
        guard isRunning, !cancelled else { return }
        cancelled = true
        status = "Canceling\u{2026}"
        runTask?.cancel()
        if let activeProvisioner {           // stop a model download that hasn't finished yet
            Task { await activeProvisioner.cancel() }
        }
    }

    // MARK: - One file

    /// The run-wide detection recipe, snapshotted in `start` so flipping a control
    /// mid-batch can't change files already in flight. The encoder/backup/caption
    /// choices travel per file in `CleanParameters`; this is just what detection runs.
    private struct Recipe {
        let modelPath: String?
        let removeFillers: Bool
        let removeRetakes: Bool
    }

    /// Clean a single queued file end to end, moving it through running →
    /// done/failed/cancelled. A single file failing marks just that item and lets
    /// the rest of the batch continue.
    private func runOne(id: QueueItem.ID, recipe: Recipe, parameters: CleanParameters) async {
        update(id) { $0.status = .running; $0.progress = 0; $0.stage = "Starting…" }
        updateRunningStatus()
        do {
            let result = try await cleanOne(id: id, recipe: recipe, parameters: parameters)
            update(id) { $0.result = result; $0.status = .done; $0.progress = 1 }
        } catch is CancellationError {
            update(id) { $0.status = .cancelled }
        } catch {
            if cancelled {
                update(id) { $0.status = .cancelled }
            } else {
                update(id) { $0.error = error.localizedDescription; $0.status = .failed }
            }
        }
        updateRunningStatus()
    }

    private func cleanOne(id: QueueItem.ID, recipe: Recipe,
                          parameters: CleanParameters) async throws -> CleanResult {
        guard let item = queue.first(where: { $0.id == id }) else { throw CancellationError() }
        let url = item.url
        let backupDir = parameters.backupOriginal ? CleanRunner.backupDirectory() : nil

        // A reviewed keep-list (from the edit timeline) renders exactly those segments:
        // serialize it to a temp JSON the engine reads, and skip the model entirely
        // (keep-file mode does no detection/transcription). The temp file is removed
        // once the run finishes.
        // Surface a write failure (don't `try?`): for a reviewed run, silently dropping
        // the keep-file would clean with freshly-detected cuts instead of the segments
        // the user approved. `map` is a no-op (no throw) for a normal, non-reviewed run.
        let tempKeepURL = try item.editedKeep.map { try Self.writeKeepFile($0) }
        let keepFilePath = tempKeepURL?.path
        defer { if let tempKeepURL { try? FileManager.default.removeItem(at: tempKeepURL) } }

        // Use the on-device classifier only for a normal (non-keep-file) clean that
        // has a filler model resolved; otherwise the engine defaults to whisper.
        let useClassifier = keepFilePath == nil && activeFillerModelPath != nil
        let options = CleanRunner.Options(modelPath: keepFilePath == nil ? recipe.modelPath : nil,
                                          removeFillers: recipe.removeFillers,
                                          removeRetakes: keepFilePath == nil && recipe.removeRetakes,
                                          backupDirectory: backupDir,
                                          waveformBuckets: keepFilePath == nil ? 120 : 0,
                                          keepFilePath: keepFilePath,
                                          fillerBackend: useClassifier ? "coreml" : "whisper",
                                          fillerModelPath: useClassifier ? activeFillerModelPath : nil)
        let result = try await CleanRunner().run(input: url, parameters: parameters, options: options) { [weak self] event in
            guard case .progress(let fraction, let label) = event else { return }
            Task { @MainActor in
                // Ignore a late callback for a file that's already finished.
                guard let self, self.isRunning,
                      self.queue.first(where: { $0.id == id })?.status == .running else { return }
                self.update(id) {
                    $0.progress = max(0, fraction)
                    if !label.isEmpty { $0.stage = label }   // keep the last stage if a tick has none
                }
            }
        }
        // Opt-in, anonymous, on-device: record a tiny feedback line for a classifier clean.
        if useClassifier, let mid = activeFeedbackModelID {
            FillerFeedback.record(modelID: mid, fillers: result.fillers,
                                  origSeconds: result.origSeconds, savedSeconds: result.savedSeconds)
        }
        return result
    }

    /// Licensing gate shared by every in-app clean entry point (`start` and
    /// `cleanReviewed`). No-op while licensing ships dark; otherwise sets a paywall
    /// message and returns false so the run never begins — defense-in-depth behind the
    /// already-disabled Clean button.
    private func ensureLicenseAllowsClean() -> Bool {
        do {
            // `checkClean()` (not `blockReason()`) so a successful GUI clean also advances
            // the rollback watermark, exactly like the headless path.
            try LicenseGate.checkClean()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Clean a single reviewed file with the user's hand-edited keep-list — the
    /// "Clean with these cuts" action from the review timeline. Unlike `start`, this
    /// touches only the one item and needs no speech model (the engine renders the
    /// given segments directly), so it runs immediately regardless of model state.
    func cleanReviewed(_ id: QueueItem.ID, keep: [ClosedRange<Double>],
                       parameters: CleanParameters) async {
        guard !isRunning,
              let idx = queue.firstIndex(where: { $0.id == id }),
              queue[idx].status == .waiting else { return }
        guard ensureLicenseAllowsClean() else { return }
        queue[idx].editedKeep = keep
        isRunning = true
        cancelled = false
        errorMessage = nil
        let work = Task { @MainActor in
            await self.runOne(id: id, recipe: Recipe(modelPath: nil, removeFillers: false,
                                                     removeRetakes: false), parameters: parameters)
        }
        runTask = work
        await work.value
        runTask = nil
        isRunning = false
        finishStatus()
    }

    /// Serialize a keep-list to a temp `{"keep": [[start, end], …]}` JSON file the
    /// engine reads via `--keep-file`. Caller removes it after the run.
    private static func writeKeepFile(_ keep: [ClosedRange<Double>]) throws -> URL {
        let pairs = keep.map { [$0.lowerBound, $0.upperBound] }
        let data = try JSONSerialization.data(withJSONObject: ["keep": pairs])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crisp-keep-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

    /// Fetch the speech model up front for an external trigger; returns nil (and
    /// leaves the model stopped) if it was canceled or failed.
    private func provisionModel(_ provisioner: ModelProvisioner) async -> String? {
        activeProvisioner = provisioner
        status = "Getting the speech model ready\u{2026}"
        defer { activeProvisioner = nil }
        do {
            let path = try await provisioner.ensureModel { [weak self] event in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    switch event {
                    case .downloading(let fraction):
                        self.status = "Downloading speech model\u{2026} \(Int(max(0, fraction) * 100))%"
                    case .verifying:
                        self.status = "Verifying speech model\u{2026}"
                    }
                }
            }
            if cancelled { isRunning = false; status = "Canceled. Your originals are untouched."; return nil }
            return path
        } catch is CancellationError {
            isRunning = false
            status = "Canceled. Your originals are untouched."
            return nil
        } catch {
            isRunning = false
            errorMessage = "Couldn\u{2019}t get the speech model ready. \(error.localizedDescription)"
            status = "Something went wrong."
            return nil
        }
    }

    private func update(_ id: QueueItem.ID, _ mutate: (inout QueueItem) -> Void) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queue[idx])
    }

    private func updateIdleStatus() {
        guard !isRunning else { return }
        let waiting = queue.filter { $0.isWaiting }
        switch waiting.count {
        case 0:  status = queue.isEmpty ? "Choose a video to begin." : status
        case 1:  status = "Ready: \(waiting[0].url.lastPathComponent)"
        default: status = "Ready: \(waiting.count) videos"
        }
    }

    private func updateRunningStatus() {
        guard isRunning else { return }
        status = "Cleaning\u{2026} \(doneCount) of \(queue.count) done"
    }

    private func finishStatus() {
        if cancelled {
            status = "Canceled. Your originals are untouched."
            return
        }
        let failed = queue.filter { $0.status == .failed }.count
        let done = doneCount
        if failed > 0 {
            errorMessage = failed == 1
                ? "1 video couldn\u{2019}t be cleaned \u{2014} see the queue for details."
                : "\(failed) videos couldn\u{2019}t be cleaned \u{2014} see the queue for details."
            status = "Finished with \(failed) error\(failed == 1 ? "" : "s")."
        } else {
            status = done == 1 ? "Done! Saved next to your original."
                               : "Done! Cleaned \(done) videos."
        }
        // Ping the user if they've switched away — the whole point of a batch is
        // walking off while it runs.
        if done > 0 {
            let saved = results.reduce(0) { $0 + $1.savedSeconds }
            Notifier.batchFinished(cleaned: done, savedSeconds: saved, failed: failed)
        }
    }
}
