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

    /// Start tracking the user's selected model (or an explicit one for tests).
    init(spec: ModelSpec = ModelProvisioner.selectedSpec()) {
        self.spec = spec
        self.provisioner = ModelProvisioner(spec: spec)
    }

    /// Absolute path the engine should load, or nil until the model is verified.
    var readyModelPath: String? { state.isReady ? provisioner.path : nil }

    /// Point the store at a different catalog model and recheck its state on disk.
    /// No-op while a download is in flight (the UI disables switching then).
    func use(_ spec: ModelSpec) async {
        guard spec != self.spec, task == nil else { return }
        self.spec = spec
        self.provisioner = ModelProvisioner(spec: spec)
        await refresh()
    }

    // MARK: - Launch check

    /// Recompute state from disk. Cheap when the file is absent; hashes the file
    /// when present to confirm it's intact.
    func refresh() async {
        if task != nil { return }   // a download is in flight; it owns the state
        state = .checking
        state = (await provisioner.existingVerifiedPath() != nil) ? .ready : .absent
    }

    // MARK: - Download (resumable)

    func download() {
        guard task == nil else { return }
        task = Task { await runDownload() }
    }

    func cancel() {
        Task { await provisioner.cancel() }   // stops the transfer; the .part is kept for resume
        task?.cancel()
        task = nil
        state = .absent
    }

    private func runDownload() async {
        state = .downloading(0)
        do {
            try await provisioner.ensureModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    // Ignore late callbacks after a cancel (which clears `task`).
                    guard let self, self.task != nil else { return }
                    switch progress {
                    case .downloading(let fraction): self.state = .downloading(fraction)
                    case .verifying:                 self.state = .verifying
                    }
                }
            }
            finishTask(.ready)
        } catch is CancellationError {
            finishTask(.absent)             // .part is kept on purpose so we can resume
        } catch let error as URLError where error.code == .cancelled {
            finishTask(.absent)
        } catch {
            Self.log.error("Model download failed: \(error.localizedDescription)")
            finishTask(.failed(Self.message(for: error)))
        }
    }

    private func finishTask(_ newState: State) {
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
