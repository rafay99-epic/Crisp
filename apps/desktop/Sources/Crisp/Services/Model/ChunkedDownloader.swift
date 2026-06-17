import Foundation

/// Streams an HTTP download to `partURL` in chunks via `URLSessionDataDelegate`.
/// Honors a Range request for resume — appends on `206`, restarts the file on a
/// plain `200` (server ignored the range) — and reports throttled `(received,
/// total)` progress. `cancel()` stops the transfer, leaving the `.part` for a
/// later resume. Delegate callbacks are serialized on the session's queue, so the
/// mutable counters are touched from one place at a time.
final class ChunkedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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
