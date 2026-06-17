import Foundation

/// Locates the bundled Python engine, its interpreter, and the tools it drives.
/// The engine ships inside the app at `Contents/Resources/engine/` (build.sh
/// copies `clean_video.py` + the `crisp` package + `bin/` there).
enum CleanEngine {
    struct NotFound: LocalizedError {
        var errorDescription: String? {
            "The cleaning engine wasn't found inside the app. Rebuild with ./build.sh."
        }
    }

    /// `clean_video.py` inside the app bundle (or the source tree during dev).
    static func scriptURL() throws -> URL {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("engine/clean_video.py")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        throw NotFound()
    }

    /// Directory of binaries vendored into the app by `build.sh`
    /// (`engine/bin/ffmpeg`, `…/ffprobe`, `…/whisper-cli`, `…/python/…`). Absent
    /// in a plain `swift run`, in which case the engine falls back to PATH.
    static var binDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("engine/bin", isDirectory: true)
    }

    /// Absolute path to a bundled tool if it shipped and is executable, else nil
    /// — nil lets the engine resolve the tool from PATH (a dev's Homebrew install).
    static func bundledTool(_ name: String) -> String? {
        guard let p = binDir?.appendingPathComponent(name).path,
              FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    /// python3 — prefer the bundled standalone runtime, then Homebrew, then system.
    static var python: String {
        if let p = binDir?.appendingPathComponent("python/bin/python3").path,
           FileManager.default.isExecutableFile(atPath: p) { return p }
        for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/usr/bin/python3"
    }
}
