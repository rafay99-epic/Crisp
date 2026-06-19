import Foundation
import CryptoKit

/// Ensures the whisper speech model the engine needs for filler-word detection is
/// on disk and intact — downloading it (resumable, hash-verified, atomic publish)
/// if absent. Headless: no `@Observable`, no UI. The app's `ModelStore` wraps this
/// for its progress UI; the background watch-folder agent and App Intents call
/// `ensureModel()` directly when an auto-clean needs fillers ("one system, not
/// two"). State is derived purely from disk + SHA-256, so an interrupted, partial,
/// corrupt, or deleted download all resolve correctly on the next call.
public actor ModelProvisioner {
    /// Download/verify progress for callers that want to surface it.
    public enum Progress: Sendable {
        case downloading(Double)   // 0…1 (negative ⇒ size unknown, indeterminate)
        case verifying
    }

    public enum ProvisionError: LocalizedError {
        case verification
        public var errorDescription: String? {
            switch self {
            case .verification: return "The downloaded model was corrupted."
            }
        }
    }

    // MARK: Model identity

    /// The catalog model this provisioner manages. Its content hash pins the exact
    /// file — `resolve/main` could in principle move, and verifying by content is
    /// what makes "corrupt / truncated / tampered" a single check.
    private nonisolated let spec: ModelSpec

    private static let log = AppInfo.logger("model")

    private nonisolated let channel: Channel
    private var downloader: ChunkedDownloader?
    /// Remembers a successful verification this process so back-to-back cleans (the
    /// watcher, a multi-file Intent) don't re-hash the whole model each time.
    private var verifiedThisSession = false

    public init(spec: ModelSpec = ModelCatalog.base, channel: Channel = .current) {
        self.spec = spec
        self.channel = channel
    }

    /// The model the user selected in settings (or the default), read from the
    /// on-disk config — so every headless surface provisions the same one.
    public static func selectedSpec() -> ModelSpec {
        ModelCatalog.spec(id: EngineConfigStore.load().selectedModelID)
    }

    /// A provisioner targeting the user's currently selected model.
    public static func forSelectedModel(channel: Channel = .current) -> ModelProvisioner {
        ModelProvisioner(spec: selectedSpec(), channel: channel)
    }

    // Paths derive from the (immutable, Sendable) channel, so they're safe to read
    // without hopping onto the actor.
    public nonisolated var modelsDir: URL {
        channel.dataDirectory.appendingPathComponent("models", isDirectory: true)
    }
    public nonisolated var fileURL: URL { modelsDir.appendingPathComponent(spec.fileName) }
    /// Absolute path the engine loads. Only trustworthy after `ensureModel`/
    /// `existingVerifiedPath` confirms the file.
    public nonisolated var path: String { fileURL.path }
    private nonisolated var partURL: URL { modelsDir.appendingPathComponent(spec.fileName + ".part") }

    /// The verified model path if it's already on disk and intact, else nil. Hashes
    /// the file (off-actor); a complete-but-wrong file is removed so the next
    /// download starts clean.
    public func existingVerifiedPath() async -> String? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            verifiedThisSession = false
            return nil
        }
        if verifiedThisSession { return url.path }   // already hashed this session
        let expected = spec.sha256
        let ok = await Task.detached(priority: .utility) { Self.sha256(of: url) == expected }.value
        if ok {
            verifiedThisSession = true
            return url.path
        }
        Self.log.error("Model on disk failed hash check — removing")
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    /// Return the verified model path, downloading (resumable) + verifying first if
    /// needed. Throws on network/verification failure; cancellation propagates and
    /// leaves the `.part` for a later resume.
    @discardableResult
    public func ensureModel(onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> String {
        if let p = await existingVerifiedPath() { return p }
        try await download(onProgress: onProgress)
        return fileURL.path
    }

    /// Stop an in-flight download (the `.part` is kept for resume).
    public func cancel() { downloader?.cancel() }

    /// Delete this model from disk (the verified file and any partial download), so
    /// the user can free space or force a clean re-download.
    public func removeFromDisk() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: partURL)
        verifiedThisSession = false
    }

    private func download(onProgress: (@Sendable (Progress) -> Void)?) async throws {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Resume from a previous partial download if one survived an interruption.
        var existing: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path),
           let size = attrs[.size] as? Int64 {
            existing = size
        }

        var request = URLRequest(url: spec.url)
        request.timeoutInterval = 60
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        onProgress?(.downloading(existing > 0 ? Double(existing) / Double(spec.approxBytes) : 0))

        // Stream to the .part file in chunks via a delegate — far cheaper than
        // iterating bytes, and it gives steady progress callbacks.
        let downloader = ChunkedDownloader(partURL: partURL, resumeOffset: existing) { received, total in
            onProgress?(.downloading(total > 0 ? Double(received) / Double(total) : -1))
        }
        self.downloader = downloader
        defer { self.downloader = nil }
        try await downloader.run(request: request)

        // Verify the completed download before trusting it.
        onProgress?(.verifying)
        let part = partURL
        let expected = spec.sha256
        let ok = await Task.detached(priority: .utility) { Self.sha256(of: part) == expected }.value
        guard ok else {
            try? FileManager.default.removeItem(at: partURL)   // corrupt → start fresh next time
            throw ProvisionError.verification
        }

        // Atomic publish: a reader only ever sees a fully-verified file.
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: partURL, to: fileURL)
        verifiedThisSession = true
    }

    /// Stream the file through SHA-256 in chunks so we never load the whole model at once.
    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
