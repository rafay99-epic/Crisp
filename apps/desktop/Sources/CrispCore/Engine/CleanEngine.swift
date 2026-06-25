import Foundation

/// Locates the bundled Python engine, its interpreter, and the tools it drives.
/// The engine ships inside the app at `Contents/Resources/engine/` (build.sh
/// copies `clean_video.py` + the `crisp` package + `bin/` there).
public enum CleanEngine {
    public struct NotFound: LocalizedError {
        public var errorDescription: String? {
            "The cleaning engine wasn't found inside the app. Rebuild with ./build.sh."
        }
    }

    /// Where `engine/` lives — `Contents/Resources` for the app. The background
    /// agent runs from `Contents/MacOS/CrispWatcher`, where `Bundle.main` isn't a
    /// reliable resource root, so it sets this once at startup to the app bundle's
    /// `Contents/Resources`. nil ⇒ fall back to `Bundle.main.resourceURL` (the
    /// app's normal case — unchanged). A process-global set once before any clean.
    public nonisolated(unsafe) static var engineRootOverride: URL?

    private static var resourceRoot: URL? {
        engineRootOverride ?? Bundle.main.resourceURL
    }

    /// `clean_video.py` inside the app bundle (or the source tree during dev).
    public static func scriptURL() throws -> URL {
        if let res = resourceRoot {
            let bundled = res.appendingPathComponent("engine/clean_video.py")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        throw NotFound()
    }

    /// Directory of binaries vendored into the app by `build.sh`
    /// (`engine/bin/ffmpeg`, `…/ffprobe`, `…/whisper-cli`, `…/python/…`). Absent
    /// in a plain `swift run`, in which case the engine falls back to PATH.
    public static var binDir: URL? {
        resourceRoot?.appendingPathComponent("engine/bin", isDirectory: true)
    }

    /// Absolute path to a bundled tool if it shipped and is executable, else nil
    /// — nil lets the engine resolve the tool from PATH (a dev's Homebrew install).
    public static func bundledTool(_ name: String) -> String? {
        guard let p = binDir?.appendingPathComponent(name).path,
              FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    /// The environment for an engine subprocess: point it at the bundled tools
    /// (each falls back to PATH if not bundled), prepend Homebrew, and tell it where
    /// to write its log. Shared by every engine spawn so they're configured alike.
    public static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let f = bundledTool("ffmpeg") { env["CRISP_FFMPEG"] = f }
        if let p = bundledTool("ffprobe") { env["CRISP_FFPROBE"] = p }
        if let w = bundledTool("whisper-cli") { env["CRISP_WHISPER"] = w }
        if let c = bundledTool("crisp-filler") { env["CRISP_FILLER"] = c }
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        env["CRISP_LOG_DIR"] = Channel.current.logsDirectory.path
        return env
    }

    /// python3 — prefer the bundled standalone runtime, then Homebrew, then system.
    public static var python: String {
        if let p = binDir?.appendingPathComponent("python/bin/python3").path,
           FileManager.default.isExecutableFile(atPath: p) { return p }
        for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/usr/bin/python3"
    }
}
