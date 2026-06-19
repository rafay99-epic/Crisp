import Foundation
import CrispCore

/// Owns the whisper speech model the engine needs for filler-word detection, as
/// UI-facing state. The download/verify/resume work lives in
/// `CrispCore.ModelProvisioner` (shared with the background agent + App Intents);
/// this type maps its progress onto an `@Observable State` the views bind to.
///
/// State is derived purely from what's on disk + its SHA-256 each launch — there
/// is no separate bookkeeping file to fall out of sync. A download interrupted by
/// quitting, a half-written file, a corrupted file, or a user who deleted the
/// model all resolve correctly on the next check.
@MainActor
@Observable
final class ModelStore {
    enum State: Equatable {
        case checking
        case ready
        case absent                 // missing / partial / failed verification
        case downloading(Double)    // 0…1 (negative ⇒ size unknown, indeterminate)
        case verifying
        case failed(String)

        var isReady: Bool { self == .ready }
        var isBusy: Bool {
            switch self {
            case .checking, .verifying: return true
            case .downloading:          return true
            default:                    return false
            }
        }
    }

    private(set) var state: State = .checking

    /// The model this store currently tracks (the user's selection). Switching it
    /// retargets the provisioner and rechecks disk.
    private(set) var spec: ModelSpec

    /// The provisioner for `spec`. Exposed so an external trigger can auto-download
    /// through the *same* instance instead of racing a second download onto the
    /// same `.part` file.
    private(set) var provisioner: ModelProvisioner
    private static let log = AppInfo.logger("model")
    private var task: Task<Void, Never>?
    /// Bumped on every transition that should invalidate work already in flight
    /// (retarget, cancel, a fresh download/check). Async callbacks capture the
    /// generation they belong to and no-op if it has moved on — so a late progress
    /// callback from a cancelled-then-restarted download can't clobber the new state.
    private var generation = 0

    /// One provisioner per model id, reused across switches so a model verified
    /// this session isn't re-hashed (148–574 MB) when the user toggles back to it.
    private var provisioners: [String: ModelProvisioner] = [:]

    /// Start tracking the user's selected model (or an explicit one for tests).
    init(spec: ModelSpec = ModelProvisioner.selectedSpec()) {
        self.spec = spec
        let p = ModelProvisioner(spec: spec)
        self.provisioner = p
        self.provisioners[spec.id] = p
    }

    /// Absolute path the engine should load, or nil until the model is verified.
    var readyModelPath: String? { state.isReady ? provisioner.path : nil }

    /// Point the store at a different catalog model and recheck its state on disk.
    /// No-op while a download is in flight (the UI disables switching then). The
    /// state drops to `.checking` synchronously so any gate reading it closes
    /// immediately, before the disk check completes.
    func use(_ spec: ModelSpec) {
        guard spec != self.spec, task == nil else { return }
        self.spec = spec
        self.provisioner = cachedProvisioner(for: spec)
        state = .checking   // synchronous: a gate reading `state` closes this frame,
        recheck()           // before the async disk check resolves to .ready/.absent
    }

    /// Reuse the existing provisioner for a model (keeping its verified-session
    /// cache), creating one the first time it's selected.
    private func cachedProvisioner(for spec: ModelSpec) -> ModelProvisioner {
        if let existing = provisioners[spec.id] { return existing }
        let p = ModelProvisioner(spec: spec)
        provisioners[spec.id] = p
        return p
    }

    // MARK: - Launch check

    /// Recompute state from disk. Cheap when the file is absent; hashes the file
    /// when present to confirm it's intact. Async; `refresh` awaits it for callers
    /// (the launch `.task`) that want to know when it's settled.
    func refresh() async {
        if task != nil { return }   // a download is in flight; it owns the state
        generation += 1
        let gen = generation
        state = .checking
        let ready = await provisioner.existingVerifiedPath() != nil
        guard gen == generation else { return }   // superseded by a newer transition
        state = ready ? .ready : .absent
    }

    /// Fire-and-forget disk recheck (used on retarget). The caller has already set
    /// `.checking` synchronously; this resolves it to `.ready`/`.absent`.
    private func recheck() {
        guard task == nil else { return }
        Task { await refresh() }
    }

    // MARK: - Download (resumable)

    func download() {
        guard task == nil else { return }
        generation += 1
        let gen = generation
        task = Task { await runDownload(gen) }
    }

    func cancel() {
        Task { await provisioner.cancel() }   // stops the transfer; the .part is kept for resume
        task?.cancel()
        task = nil
        generation += 1                        // invalidate any late callbacks from the cancelled run
        state = .absent
    }

    /// Delete the currently tracked model from disk and recheck state. No-op while a
    /// download is in flight.
    func deleteSelected() async {
        guard task == nil else { return }
        await provisioner.removeFromDisk()
        await refresh()
    }

    private func runDownload(_ gen: Int) async {
        state = .downloading(0)
        do {
            try await provisioner.ensureModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    // Ignore callbacks from a superseded run (cancelled / retargeted).
                    guard let self, self.generation == gen, self.task != nil else { return }
                    switch progress {
                    case .downloading(let fraction): self.state = .downloading(fraction)
                    case .verifying:                 self.state = .verifying
                    }
                }
            }
            finishTask(.ready, gen)
        } catch is CancellationError {
            finishTask(.absent, gen)             // .part is kept on purpose so we can resume
        } catch let error as URLError where error.code == .cancelled {
            finishTask(.absent, gen)
        } catch {
            Self.log.error("Model download failed: \(error.localizedDescription)")
            finishTask(.failed(Self.message(for: error)), gen)
        }
    }

    private func finishTask(_ newState: State, _ gen: Int) {
        guard gen == generation else { return }   // a newer transition already took over
        state = newState
        task = nil
    }

    private static func message(for error: Error) -> String {
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "No internet connection. Connect and try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
