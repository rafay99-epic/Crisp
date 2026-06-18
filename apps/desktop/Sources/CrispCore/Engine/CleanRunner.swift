import Foundation

/// Drives the Python engine as a subprocess for **one** input file, streaming its
/// `--ndjson` events and returning the `CleanResult`. Knows nothing about the UI —
/// the app's `CleanModel`, the "Clean with Crisp" Service/App Intent, and the
/// background watch-folder agent all run cleans through this one path ("one
/// system, not two"). Honors `Task` cancellation: cancelling the surrounding task
/// terminates the subprocess (the original is never touched, so this is safe).
public struct CleanRunner {
    /// One line of the engine's `--ndjson` output.
    private struct Event: Decodable {
        let event: String
        var message: String?
        var fraction: Double?
        var label: String?
        var output: String?
        var orig_seconds: Double?
        var new_seconds: Double?
        var saved_seconds: Double?
        var pauses: Int?
        var fillers: Int?
        var peaks: [Double]?
        var removed: [Bool]?
        var video_output: String?
        var audio_output: String?
    }

    /// A progress signal for the one file being cleaned. `fraction` is 0…1 for this
    /// file alone; callers driving a multi-file run map it onto an overall bar.
    public enum Progress: Sendable {
        case log(String)
        case progress(fraction: Double, label: String)
    }

    /// The non-strength inputs to a clean: which model (if any), whether to strip
    /// fillers, and where to back the original up (nil ⇒ `--no-backup`).
    public struct Options: Sendable {
        public var modelPath: String?
        public var removeFillers: Bool
        public var backupDirectory: URL?
        /// >0 asks the engine to emit an N-bucket waveform for the UI (the bare
        /// CLI / watcher leave it 0 so they don't pay for data nothing renders).
        public var waveformBuckets: Int
        public init(modelPath: String? = nil, removeFillers: Bool,
                    backupDirectory: URL? = nil, waveformBuckets: Int = 0) {
            self.modelPath = modelPath
            self.removeFillers = removeFillers
            self.backupDirectory = backupDirectory
            self.waveformBuckets = waveformBuckets
        }
    }

    /// File extensions Crisp treats as cleanable video, lowercased. Shared by the
    /// drop zone, the Finder Service, and the watch folder so they all agree.
    public static let videoExtensions: Set<String> =
        ["mov", "mp4", "mkv", "m4v", "avi", "webm", "flv"]

    public init() {}

    /// The exact argv passed to `clean_video.py` (excluding the python interpreter).
    /// Pulled out as a pure function so the flag mapping can be unit-tested without
    /// spawning a subprocess.
    public static func arguments(scriptPath: String, input: URL,
                                 parameters: CleanParameters, options: Options) -> [String] {
        var args = [
            scriptPath, input.path,
            "--pause", String(parameters.pause),
            "--noise", String(parameters.noiseDB),
            "--keep-pause", String(parameters.keepPause),
            "--min-keep", String(parameters.minKeep),
            "--video-codec", parameters.videoCodec,
            "--quality", parameters.videoQuality,
            "--audio-codec", parameters.audioCodec,
            "--audio-bitrate", String(parameters.audioBitrateKbps),
            "--container", parameters.outputContainer,
            "--ndjson"
        ]
        if parameters.hardwareEncoding { args.append("--hardware") }
        if parameters.splitTracks {
            args.append("--split")
            args += ["--split-audio", parameters.splitAudioFormat]
        }
        if !parameters.outputDirectory.isEmpty { args += ["--out-dir", parameters.outputDirectory] }
        if options.removeFillers, let model = options.modelPath { args += ["--model", model] }
        if !options.removeFillers { args.append("--no-fillers") }
        if options.waveformBuckets > 0 { args += ["--waveform", String(options.waveformBuckets)] }
        if let dir = options.backupDirectory {
            args += ["--backup-dir", dir.path]
        } else {
            args.append("--no-backup")
        }
        return args
    }

    /// Spawn `clean_video.py … --ndjson`, stream events to `onEvent`, and return the
    /// result. Throws on the engine's `error` event, a missing result, or a tool
    /// that couldn't be found.
    public func run(input: URL, parameters: CleanParameters, options: Options,
                    onEvent: @escaping @Sendable (Progress) -> Void) async throws -> CleanResult {
        let script = try CleanEngine.scriptURL()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CleanEngine.python)
        proc.arguments = Self.arguments(scriptPath: script.path, input: input,
                                        parameters: parameters, options: options)

        var env = ProcessInfo.processInfo.environment
        // Point the engine at the binaries we ship; each falls back to PATH if it
        // wasn't bundled (e.g. a plain `swift run` on a dev machine).
        if let f = CleanEngine.bundledTool("ffmpeg") { env["CRISP_FFMPEG"] = f }
        if let p = CleanEngine.bundledTool("ffprobe") { env["CRISP_FFPROBE"] = p }
        if let w = CleanEngine.bundledTool("whisper-cli") { env["CRISP_WHISPER"] = w }
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        return try await withTaskCancellationHandler {
            try proc.run()
            var result: CleanResult?
            let decoder = JSONDecoder()
            for try await line in outPipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let ev = try? decoder.decode(Event.self, from: data) else { continue }
                switch ev.event {
                case "log":
                    if let m = ev.message { onEvent(.log(m)) }
                case "progress":
                    onEvent(.progress(fraction: ev.fraction ?? 0, label: ev.label ?? ""))
                case "result":
                    result = CleanResult(
                        output: ev.output ?? "",
                        origSeconds: ev.orig_seconds ?? 0,
                        newSeconds: ev.new_seconds ?? 0,
                        savedSeconds: ev.saved_seconds ?? 0,
                        pauses: ev.pauses ?? 0,
                        fillers: ev.fillers ?? 0,
                        peaks: ev.peaks ?? [],
                        removed: ev.removed ?? [],
                        videoOutput: ev.video_output ?? "",
                        audioOutput: ev.audio_output ?? "")
                case "error":
                    throw NSError(domain: "Crisp", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: ev.message ?? "Unknown error"])
                default:
                    break
                }
            }
            proc.waitUntilExit()
            if Task.isCancelled { throw CancellationError() }
            guard let result else {
                throw NSError(domain: "Crisp", code: 2, userInfo:
                    [NSLocalizedDescriptionKey: "The engine finished without producing a result."])
            }
            return result
        } onCancel: {
            proc.terminate()
        }
    }

    // MARK: - Backup locations

    /// The folder all backed-up originals live under (`~/.crisp*/Originals/`).
    /// Each run drops into a dated subfolder beneath it; this is the stable parent
    /// the UI shows and reveals in Finder.
    public static var backupParentDirectory: URL {
        Channel.current.dataDirectory.appendingPathComponent("Originals", isDirectory: true)
    }

    /// Where backed-up originals are kept: a date-stamped folder under the
    /// channel's data home (`~/.crisp*/Originals/2026-06-18/`). Grouping by day
    /// keeps a session's originals together without cluttering the source folder.
    public static func backupDirectory(for date: Date = Date()) -> URL {
        backupParentDirectory.appendingPathComponent(dayFormatter.string(from: date),
                                                     isDirectory: true)
    }

    /// Stable `2026-06-18` folder names — fixed locale/format so they sort and
    /// never shift with the user's region settings.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
