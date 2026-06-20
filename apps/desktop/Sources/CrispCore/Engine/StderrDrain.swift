import Foundation

/// Continuously drains a child process's **stderr** via a `readabilityHandler`
/// (a `DispatchSource`-backed callback), bounded to the most recent bytes.
///
/// Why not `FileHandle.bytes.lines`: two concurrent `FileHandle.AsyncBytes`
/// readers (one for stdout, one for stderr) contend on a shared internal serial
/// queue. When the stderr reader blocks waiting on an empty pipe — the normal case,
/// since the engine routes its detail to a log file — it **starves the stdout
/// reader**, so stdout is only delivered in one burst at EOF. That froze the live
/// progress bar at 0% for the whole clean. `readabilityHandler` uses an independent
/// source, so the stdout `bytes.lines` reader streams freely.
///
/// Still serves the original purpose: a stderr flood (e.g. a Python traceback) is
/// drained as it arrives, so it can't fill the pipe buffer and deadlock the writer.
final class StderrDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()
    private let cap = 64 * 1024   // keep only the most recent 64 KB (root cause is at the end)

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            self.lock.lock()
            self.data.append(chunk)
            if self.data.count > self.cap { self.data.removeFirst(self.data.count - self.cap) }
            self.lock.unlock()
        }
    }

    /// Stop draining and return the captured stderr as lines. Call after the process
    /// has exited (so the handler has already received the final flush).
    func finish() -> [String] {
        handle.readabilityHandler = nil
        lock.lock(); defer { lock.unlock() }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
