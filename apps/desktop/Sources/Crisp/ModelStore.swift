import Foundation
import CryptoKit
import os

/// Owns the whisper speech model the engine needs for filler-word detection.
///
/// The model (~148 MB) is *not* shipped inside the app — that would bloat every
/// build and re-download on every update. Instead it lives once in the channel's
/// data home (`~/.crisp/models/…`) and is fetched on first run. The shipped
/// binaries (ffmpeg / whisper-cli / python) ARE bundled and signed with the app;
/// only this large, rarely-changing blob is downloaded.
///
/// State is derived purely from what's on disk + its SHA-256 each launch — there
/// is no separate bookkeeping file to fall out of sync. So a download interrupted
/// by quitting the app, a half-written file, a corrupted file, or a user who
/// deleted the model all resolve correctly on the next check: a partial download
/// resumes from where it stopped (HTTP Range), anything that fails verification is
/// re-fetched, and a verified file is used as-is.
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

    // MARK: Pinned model identity

    /// `ggml-base.en.bin` from the whisper.cpp model repo. The hash pins the exact
    /// file — `resolve/main` could in principle move, and verifying by content is
    /// what makes "corrupt / truncated / tampered" a single check.
    private static let fileName = "ggml-base.en.bin"
    private static let url = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
    private static let expectedSHA256 =
        "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
    /// Used only to show a sensible progress bar before the server reports a size.
    private static let approxBytes: Int64 = 147_964_211

    private static let log = Logger(subsystem: "com.syntaxlabtechnology.crisp",
                                    category: "model")

    private let modelsDir = Channel.current.dataDirectory
        .appendingPathComponent("models", isDirectory: true)
    private var fileURL: URL { modelsDir.appendingPathComponent(Self.fileName) }
    private var partURL: URL { modelsDir.appendingPathComponent(Self.fileName + ".part") }

    /// Absolute path the engine should load, or nil until the model is verified.
    var readyModelPath: String? { state.isReady ? fileURL.path : nil }

    private var task: Task<Void, Never>?
    private var downloader: ChunkedDownloader?

    // MARK: - Launch check

    /// Recompute state from disk. Cheap when the file is absent; hashes the file
    /// when present (off the main actor) to confirm it's intact.
    func refresh() async {
        if task != nil { return }   // a download is in flight; it owns the state
        state = .checking
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .absent
            return
        }
        let expected = Self.expectedSHA256
        let ok = await Task.detached(priority: .utility) {
            Self.sha256(of: url) == expected
        }.value
        if ok {
            state = .ready
        } else {
            // A complete-but-wrong file is junk; drop it so the next download is clean.
            Self.log.error("Model on disk failed hash check — removing")
            try? FileManager.default.removeItem(at: url)
            state = .absent
        }
    }

    // MARK: - Download (resumable)

    func download() {
        guard task == nil else { return }
        task = Task { await runDownload() }
    }

    func cancel() {
        downloader?.cancel()        // stops the URLSession task; the .part is kept for resume
        task?.cancel()
        task = nil
        state = .absent
    }

    private func finishTask(_ newState: State) {
        state = newState
        task = nil
    }

    private func runDownload() async {
        do {
            try FileManager.default.createDirectory(at: modelsDir,
                                                    withIntermediateDirectories: true)

            // Resume from a previous partial download if one survived an app quit.
            var existing: Int64 = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path),
               let size = attrs[.size] as? Int64 {
                existing = size
            }

            var request = URLRequest(url: Self.url)
            request.timeoutInterval = 60
            if existing > 0 {
                request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            }

            state = .downloading(existing > 0 ? Double(existing) / Double(Self.approxBytes) : 0)

            // Stream to the .part file in chunks via a delegate — far cheaper than
            // iterating bytes, and it gives steady progress callbacks.
            let downloader = ChunkedDownloader(partURL: partURL, resumeOffset: existing) { [weak self] received, total in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(total > 0 ? Double(received) / Double(total) : -1)
                }
            }
            self.downloader = downloader
            try await downloader.run(request: request)
            self.downloader = nil

            // Verify the completed download before trusting it.
            state = .verifying
            let part = partURL
            let expected = Self.expectedSHA256
            let ok = await Task.detached(priority: .utility) {
                Self.sha256(of: part) == expected
            }.value
            guard ok else {
                try? FileManager.default.removeItem(at: partURL)   // corrupt → start fresh next time
                throw Err.verification
            }

            // Atomic publish: a reader only ever sees a fully-verified file.
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: partURL, to: fileURL)
            finishTask(.ready)
        } catch is CancellationError {
            finishTask(.absent)             // .part is kept on purpose so we can resume
        } catch let error as URLError where error.code == .cancelled {
            finishTask(.absent)
        } catch {
            self.downloader = nil
            Self.log.error("Model download failed: \(error.localizedDescription)")
            finishTask(.failed(Self.message(for: error)))
        }
    }

    // MARK: - Helpers

    private enum Err: LocalizedError {
        case http(Int)
        case verification
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Download failed (HTTP \(code))."
            case .verification:   return "The downloaded model was corrupted."
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "No internet connection. Connect and try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Stream the file through SHA-256 in chunks so we never load 148 MB at once.
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

/// Streams an HTTP download to `partURL` in chunks via `URLSessionDataDelegate`.
/// Honors a Range request for resume — appends on `206`, restarts the file on a
/// plain `200` (server ignored the range) — and reports throttled `(received,
/// total)` progress. `cancel()` stops the transfer, leaving the `.part` for a
/// later resume. Delegate callbacks are serialized on the session's queue, so the
/// mutable counters are touched from one place at a time.
private final class ChunkedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let partURL: URL
    private let resumeOffset: Int64
    private let onProgress: @Sendable (Int64, Int64) -> Void

    private var handle: FileHandle?
    private var received: Int64 = 0
    private var total: Int64 = 0
    private var responseError: Error?
    private var lastReported = Date.distantPast

    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?

    init(partURL: URL, resumeOffset: Int64,
         onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.partURL = partURL
        self.resumeOffset = resumeOffset
        self.onProgress = onProgress
    }

    private enum Err: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Download failed (HTTP \(code))."
            }
        }
    }

    func run(request: URLRequest) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            session.dataTask(with: request).resume()
        }
    }

    func cancel() { session?.invalidateAndCancel() }

    // Validate status, choose append-vs-restart, and open the file handle.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            responseError = Err.http((response as? HTTPURLResponse)?.statusCode ?? -1)
            completionHandler(.cancel)
            return
        }
        let resuming = http.statusCode == 206
        received = resuming ? resumeOffset : 0
        total = Self.total(from: http, alreadyHave: received)
        do {
            if resuming, FileManager.default.fileExists(atPath: partURL.path) {
                handle = try FileHandle(forWritingTo: partURL)
                try handle?.seekToEnd()
            } else {
                try? FileManager.default.removeItem(at: partURL)
                FileManager.default.createFile(atPath: partURL.path, contents: nil)
                handle = try FileHandle(forWritingTo: partURL)
            }
            completionHandler(.allow)
        } catch {
            responseError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            let now = Date()
            if now.timeIntervalSince(lastReported) > 0.1 {       // throttle UI updates
                lastReported = now
                onProgress(received, total)
            }
        } catch {
            responseError = error
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        let cont = continuation
        continuation = nil
        if let responseError {
            cont?.resume(throwing: responseError)
        } else if let error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume()
        }
    }

    /// Total size from `Content-Range: …/<total>`, else `Content-Length` (+ what we
    /// already have), else 0 ⇒ indeterminate progress.
    private static func total(from http: HTTPURLResponse, alreadyHave: Int64) -> Int64 {
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = range.split(separator: "/").last,
           let parsed = Int64(slash.trimmingCharacters(in: .whitespaces)) {
            return parsed
        }
        if http.expectedContentLength > 0 { return alreadyHave + http.expectedContentLength }
        return 0
    }
}
