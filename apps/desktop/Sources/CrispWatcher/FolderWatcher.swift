import Foundation
import CoreServices

/// Thin wrapper over an `FSEventStream` watching a single folder (recursively) for
/// file-level changes. Reports the changed paths on `queue`; the controller
/// decides which are new recordings worth cleaning. Start/stop are idempotent so
/// the folder can be re-pointed when settings change.
final class FolderWatcher {
    private let folder: URL
    private let queue: DispatchQueue
    private let onPaths: ([String]) -> Void
    private var stream: FSEventStreamRef?

    init(folder: URL, queue: DispatchQueue, onPaths: @escaping ([String]) -> Void) {
        self.folder = folder
        self.queue = queue
        self.onPaths = onPaths
    }

    func start() {
        guard stream == nil else { return }
        let callback: FSEventStreamCallback = { _, info, count, pathsPtr, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPtr, to: CFArray.self) as? [String] ?? []
            if !paths.isEmpty { watcher.onPaths(paths) }
            _ = count
        }
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,                         // coalesce bursts over 1s
            flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
