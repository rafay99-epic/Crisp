import Foundation
import CrispCore
import UserNotifications

/// The brain of the watch-folder agent. Watches the chosen folder for new
/// recordings and the settings file for changes, debounces until a dropped file
/// finishes writing, then cleans each one serially through the shared `QuickClean`
/// path. All state is touched on a single serial queue, so no locking is needed —
/// which is what makes the `@unchecked Sendable` conformance safe.
final class WatchController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.syntaxlabtechnology.crisp.watcher")
    private let log = AppInfo.logger("watcher")

    private var config = EngineConfig.defaults
    /// One provisioner reused across a batch so the session verification cache hits
    /// (a 10-file drop doesn't re-hash the model 10×). Re-targeted when the selected
    /// model changes in the config.
    private var provisioner = ModelProvisioner.forSelectedModel()
    private var folderWatcher: FolderWatcher?
    private let configWatcher: FolderWatcher

    // Files seen changing but not yet stable: path → (lastSize, lastChangedAt).
    private var pending: [String: (size: Int64, at: Date)] = [:]
    private var stabilityTimer: DispatchSourceTimer?

    // Serial cleaning.
    private var jobs: [URL] = []
    private var busy = false
    private var seen: Set<String> = []   // enqueued this session, to avoid repeats

    /// How long a file's size must hold steady before we treat the write as done.
    private let settleSeconds: TimeInterval = 2

    init() {
        // Watch the config directory so toggling settings (folder, fillers) while
        // the agent is alive takes effect without a restart.
        let configDir = EngineConfigStore.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        var reload: (() -> Void)?
        configWatcher = FolderWatcher(folder: configDir, queue: queue) { _ in reload?() }
        reload = { [weak self] in self?.reloadConfig() }
    }

    /// Start watching. Blocks the calling thread on the run loop (the agent's main).
    func run() {
        queue.async { [weak self] in
            guard let self else { return }
            self.config = EngineConfigStore.load()
            self.configWatcher.start()
            self.reconfigureFolder()
            self.startStabilityTimer()
            self.log.info("Watcher started (enabled=\(self.config.watchEnabled), folder=\(self.config.watchFolderPath, privacy: .public))")
        }
        requestNotificationAuthorization()
        dispatchMain()
    }

    // MARK: - Config

    private func reloadConfig() {
        let new = EngineConfigStore.load()
        guard new != config else { return }
        let folderChanged = new.watchFolderPath != config.watchFolderPath
            || new.watchEnabled != config.watchEnabled
        if new.selectedModelID != config.selectedModelID {
            provisioner = ModelProvisioner(spec: ModelCatalog.spec(id: new.selectedModelID))
        }
        config = new
        if folderChanged { reconfigureFolder() }
    }

    private func reconfigureFolder() {
        folderWatcher?.stop()
        folderWatcher = nil
        pending.removeAll()
        guard config.watchEnabled, !config.watchFolderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: config.watchFolderPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            log.error("Watch folder doesn't exist: \(folder.path, privacy: .public)")
            return
        }
        let watcher = FolderWatcher(folder: folder, queue: queue) { [weak self] paths in
            self?.handle(paths: paths)
        }
        watcher.start()
        folderWatcher = watcher
        log.info("Watching \(folder.path, privacy: .public)")
        scanExisting(folder)
    }

    /// Catch up on un-cleaned videos already sitting in the folder when we start —
    /// FSEvents only reports changes since launch, so a file dropped while the agent
    /// wasn't running (Mac off, a cloud sync) would otherwise be missed. Files that
    /// already have a `_cleaned` sibling are skipped, so this never re-does work.
    private func scanExisting(_ folder: URL) {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in entries where isCleanableInput(url) {
            enqueue(url.resolvingSymlinksInPath())
        }
    }

    // MARK: - Change handling + stability

    private func handle(paths: [String]) {
        // Resolve symlinks on both sides: FSEvents reports canonical paths
        // (e.g. /private/tmp/…), so comparing against a symlinked watch path
        // (/tmp/…) would never match without this.
        let folder = URL(fileURLWithPath: config.watchFolderPath).resolvingSymlinksInPath().path
        for path in paths {
            let url = URL(fileURLWithPath: path)
            // Only files directly in the watched folder (not deeper), that look like
            // a fresh recording we haven't already handled.
            guard url.deletingLastPathComponent().resolvingSymlinksInPath().path == folder,
                  isCleanableInput(url), !seen.contains(url.path) else { continue }
            pending[url.path] = (size: fileSize(url), at: Date())
        }
    }

    private func startStabilityTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.checkPending() }
        timer.resume()
        stabilityTimer = timer
    }

    private func checkPending() {
        guard !pending.isEmpty else { return }
        let now = Date()
        for (path, info) in pending {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { pending[path] = nil; continue }
            let size = fileSize(url)
            if size != info.size {
                pending[path] = (size: size, at: now)              // still growing — reset the clock
            } else if size > 0, now.timeIntervalSince(info.at) >= settleSeconds {
                pending[path] = nil                                 // settled — clean it
                enqueue(url)
            }
        }
    }

    // MARK: - Cleaning queue

    private func enqueue(_ url: URL) {
        guard !seen.contains(url.path) else { return }
        seen.insert(url.path)
        jobs.append(url)
        processNext()
    }

    private func processNext() {
        guard !busy, !jobs.isEmpty else { return }
        busy = true
        let url = jobs.removeFirst()
        let removeFillers = config.watchRemoveFillers
        // Reuse the held provisioner (re-targeted on config change) so a batch
        // shares one verification instead of re-hashing the model per file.
        let provisioner = self.provisioner
        log.info("Cleaning \(url.lastPathComponent, privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await QuickClean().clean(url, strength: .aggressive,
                                                          removeFillers: removeFillers,
                                                          provisioner: provisioner)
                self.queue.async { self.finished(url, output: result.output, error: nil) }
            } catch {
                self.queue.async { self.finished(url, output: nil, error: error) }
            }
        }
    }

    private func finished(_ url: URL, output: String?, error: Error?) {
        busy = false
        if let output {
            log.info("Cleaned \(url.lastPathComponent, privacy: .public) → \(URL(fileURLWithPath: output).lastPathComponent, privacy: .public)")
            notify(title: "Cleaned \(url.lastPathComponent)",
                   body: "Saved \(URL(fileURLWithPath: output).lastPathComponent) to the watched folder.")
        } else if let error {
            log.error("Failed to clean \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        processNext()
    }

    // MARK: - Helpers

    private func isCleanableInput(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        guard CleanRunner.videoExtensions.contains(url.pathExtension.lowercased()),
              !Self.isCleanedOutputName(name) else { return false }

        if config.outputDirectory.isEmpty {
            // Beside the source: a cleaned sibling means it's done. No cross-source
            // collisions are possible here (each source has its own folder).
            let folder = url.deletingLastPathComponent()
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return !siblings.contains { $0.hasPrefix(name + "_cleaned.") }
        }

        // Shared output folder: only skip if one of *this* source's cleaned outputs
        // (tagged with this exact source path) already exists. A different file that
        // happens to share a name still gets cleaned — the engine writes it a _N
        // copy rather than overwriting.
        let folder = URL(fileURLWithPath: config.outputDirectory, isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let source = url.resolvingSymlinksInPath().path
        return !entries.contains { entry in
            entry.hasPrefix(name + "_cleaned.") || entry.hasPrefix(name + "_cleaned_")
                ? OutputTag.source(ofFileAt: folder.appendingPathComponent(entry).path) == source
                : false
        }
    }

    /// True for the engine's own cleaned outputs — `<name>_cleaned` and the
    /// `<name>_cleaned_<n>` copies a shared output folder can produce — so the
    /// watcher never re-ingests them when the output folder is the watched one.
    private static func isCleanedOutputName(_ name: String) -> Bool {
        guard let range = name.range(of: "_cleaned", options: .backwards) else { return false }
        let tail = name[range.upperBound...]                       // "" or "_3"
        return tail.isEmpty || (tail.first == "_" && tail.dropFirst().allSatisfy(\.isNumber) && tail.count > 1)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    // MARK: - Notifications (best-effort)

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
