import Foundation
import SwiftUI
import CrispCore

/// Drives the cleaning of the user's chosen files and publishes progress/results to
/// the UI. The actual subprocess work lives in `CrispCore.CleanRunner` (shared with
/// the Finder Service, the App Intent, and the watch-folder agent); this type owns
/// the multi-file loop, the observable state the views bind to, and cancellation.
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

    /// The in-flight clean, so `cancel()` can stop it mid-run (cancelling the task
    /// terminates the engine subprocess via `CleanRunner`'s cancellation handler).
    private var runTask: Task<Void, Never>?
    private var cancelled = false
    /// A model download in flight (only during an auto-provisioning start), so
    /// `cancel()` can stop it before the clean loop even begins.
    private var activeProvisioner: ModelProvisioner?

    func addFiles(_ urls: [URL]) {
        let videos = urls.filter { CleanRunner.videoExtensions.contains($0.pathExtension.lowercased()) }
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
    /// user turned fillers off — pauses-only needs no model). `parameters` are the
    /// numeric cutting knobs derived from the chosen strength (or custom settings).
    ///
    /// `provisioner` is used only by external triggers (the Finder Service) that
    /// may run before the model is downloaded: when fillers are on and no
    /// `modelPath` is given, the model is fetched first (progress shown in the
    /// window). The normal in-app path passes a ready `modelPath` and no
    /// provisioner, so this step is skipped.
    func start(modelPath: String?, parameters: CleanParameters,
               provisioner: ModelProvisioner? = nil) async {
        guard !files.isEmpty, !isRunning else { return }
        isRunning = true
        cancelled = false
        results = []
        errorMessage = nil
        logLines = []
        progress = 0

        var resolvedModel = modelPath
        if removeFillers, resolvedModel == nil, let provisioner {
            activeProvisioner = provisioner
            status = "Getting the speech model ready\u{2026}"
            do {
                resolvedModel = try await provisioner.ensureModel { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.isRunning else { return }
                        switch event {
                        case .downloading(let fraction):
                            self.progress = max(0, fraction)
                            self.status = "Downloading speech model\u{2026}"
                        case .verifying:
                            self.status = "Verifying speech model\u{2026}"
                        }
                    }
                }
            } catch is CancellationError {
                activeProvisioner = nil
                isRunning = false
                status = "Canceled. Your original is untouched."
                progress = 0
                return
            } catch {
                activeProvisioner = nil
                isRunning = false
                errorMessage = "Couldn\u{2019}t get the speech model ready. \(error.localizedDescription)"
                status = "Something went wrong."
                return
            }
            activeProvisioner = nil
            if cancelled {
                isRunning = false
                status = "Canceled. Your original is untouched."
                progress = 0
                return
            }
            progress = 0
        }

        let fileList = files
        let total = Double(fileList.count)
        let work = Task { @MainActor in
            for (idx, url) in fileList.enumerated() {
                if Task.isCancelled { break }
                let base = Double(idx) / total
                let span = 1.0 / total
                if fileList.count > 1 {
                    logLines.append("\u{2014} Video \(idx + 1) of \(fileList.count): \(url.lastPathComponent)")
                }
                do {
                    let result = try await cleanOne(url, base: base, span: span,
                                                    modelPath: resolvedModel, parameters: parameters)
                    results.append(result)
                } catch is CancellationError {
                    break
                } catch {
                    if cancelled { break }
                    errorMessage = error.localizedDescription
                    status = "Something went wrong."
                    break
                }
            }
        }
        runTask = work
        await work.value
        runTask = nil

        isRunning = false
        if cancelled {
            status = "Canceled. Your original is untouched."
            progress = 0
        } else if errorMessage == nil {
            progress = 1
            status = "Done! Saved next to your original."
        }
    }

    /// Stop the in-progress clean. The original is never modified, so canceling is
    /// always safe; a partially-rendered output may be left beside it.
    func cancel() {
        guard isRunning, !cancelled else { return }
        cancelled = true
        status = "Canceling\u{2026}"
        runTask?.cancel()
        if let activeProvisioner {           // stop a model download that hasn't finished yet
            Task { await activeProvisioner.cancel() }
        }
    }

    private func cleanOne(_ url: URL, base: Double, span: Double,
                          modelPath: String?, parameters: CleanParameters) async throws -> CleanResult {
        let backupDir = parameters.backupOriginal ? CleanRunner.backupDirectory() : nil
        let options = CleanRunner.Options(modelPath: modelPath,
                                          removeFillers: removeFillers,
                                          backupDirectory: backupDir)
        return try await CleanRunner().run(input: url, parameters: parameters, options: options) { [weak self] event in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                switch event {
                case .log(let message):
                    self.logLines.append(message)
                case .progress(let fraction, let label):
                    self.progress = base + span * fraction
                    if !label.isEmpty { self.status = label }
                }
            }
        }
    }
}
