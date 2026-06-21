import Foundation

/// Drives the Python engine as a subprocess for **one** input file, streaming its
/// `--ndjson` events and returning the `CleanResult`. Knows nothing about the UI —
/// the app's `CleanModel`, the "Clean with Crisp" Service/App Intent, and the
/// background watch-folder agent all run cleans through this one path ("one
/// system, not two"). Honors `Task` cancellation: cancelling the surrounding task
/// terminates the subprocess (the original is never touched, so this is safe).
public struct CleanRunner {
    private static let log = AppInfo.logger("clean")
    private static let engineLog = AppInfo.logger("engine")

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
        var srt_output: String?
        var vtt_output: String?
        var backup: String?
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
        /// An explicit reviewed keep-list (the edit timeline's output): the path to a
        /// `{"keep": [[start, end], ...]}` JSON. When set, the engine renders exactly
        /// those segments and skips detection/transcription/model entirely.
        public var keepFilePath: String?
        /// Filler-detection backend: "whisper" (default) or "coreml" (the on-device
        /// classifier). For "coreml", `fillerModelPath` is the .mlmodel to run.
        public var fillerBackend: String
        public var fillerModelPath: String?
        public init(modelPath: String? = nil, removeFillers: Bool,
                    backupDirectory: URL? = nil, waveformBuckets: Int = 0,
                    keepFilePath: String? = nil,
                    fillerBackend: String = "whisper", fillerModelPath: String? = nil) {
            self.modelPath = modelPath
            self.removeFillers = removeFillers
            self.backupDirectory = backupDirectory
            self.waveformBuckets = waveformBuckets
            self.keepFilePath = keepFilePath
            self.fillerBackend = fillerBackend
            self.fillerModelPath = fillerModelPath
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
        // A reviewed keep-list renders exactly those segments — no detection, so no
        // model, captions, waveform, or filler flags (all moot in keep-file mode).
        if let keepFile = options.keepFilePath {
            args += ["--keep-file", keepFile]
        } else {
            if parameters.captionsFormat != "none" { args += ["--captions", parameters.captionsFormat] }
            // The model is needed for the transcript — for filler removal *or* captions
            // (which re-time the same transcription onto the cut timeline).
            let needsTranscript = options.removeFillers || parameters.captionsFormat != "none"
            if needsTranscript, let model = options.modelPath { args += ["--model", model] }
            // Opt-in: detect fillers with the on-device classifier instead of whisper.
            // Only when we have a filler model to run; otherwise the engine defaults to whisper.
            if needsTranscript, options.fillerBackend == "coreml", let fillerModel = options.fillerModelPath {
                args += ["--filler-backend", "coreml", "--filler-model", fillerModel]
            }
            if !options.removeFillers { args.append("--no-fillers") }
            if options.waveformBuckets > 0 { args += ["--waveform", String(options.waveformBuckets)] }
        }
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

        proc.environment = CleanEngine.environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        Self.log.info("Clean start: \(input.lastPathComponent) [\(parameters.videoCodec)/\(parameters.audioCodec) q=\(parameters.videoQuality) hw=\(parameters.hardwareEncoding) fillers=\(options.removeFillers)]")

        // Drain the engine's stderr via a readabilityHandler (NOT a second
        // `bytes.lines`): two concurrent FileHandle.AsyncBytes readers contend on a
        // shared serial queue, and the stderr reader — blocked on a normally-empty
        // pipe — would starve the stdout reader, delivering all progress in one burst
        // at EOF (the live progress bar stayed frozen at 0%). A readabilityHandler is
        // an independent source, so stdout streams; it still drains stderr promptly so
        // a flood can't fill the pipe and deadlock the writer.
        let stderrDrain = StderrDrain(errPipe.fileHandleForReading)

        do {
            let result = try await withTaskCancellationHandler {
                // If the task was already cancelled before the handler was installed,
                // don't launch the engine at all (the onCancel handler can't, since the
                // process isn't running yet).
                if Task.isCancelled {
                    try? errPipe.fileHandleForWriting.close()
                    throw CancellationError()
                }
                do {
                    try proc.run()
                } catch {
                    // The child never started, so nothing will ever close the pipe's
                    // write end — close our copy so the stderr drain task hits EOF
                    // and returns instead of hanging this clean forever.
                    try? errPipe.fileHandleForWriting.close()
                    throw error
                }
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
                            audioOutput: ev.audio_output ?? "",
                            srtOutput: ev.srt_output ?? "",
                            vttOutput: ev.vtt_output ?? "",
                            backup: ev.backup ?? "")
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
                // Guard against terminating an unlaunched process: if the task is
                // already cancelled when the handler is installed it fires immediately,
                // before `proc.run()`, and `terminate()` then throws an uncaught
                // NSInvalidArgumentException ("task not launched") that crashes the app.
                if proc.isRunning { proc.terminate() }
            }
            Self.logEngineStderr(stderrDrain.finish())
            Self.log.info("Clean done: \(input.lastPathComponent) → \(URL(fileURLWithPath: result.output).lastPathComponent) (saved \(Int(result.savedSeconds))s, \(result.fillers) fillers, \(result.pauses) pauses)")
            // Record to History from this shared path, so the queue, watch-folder
            // agent, App Intent, and menu-bar drop all land in one timeline.
            if !result.output.isEmpty {
                HistoryStore.shared.record(HistoryEntry(input: input, result: result, date: Date()))
            }
            return result
        } catch {
            Self.logEngineStderr(stderrDrain.finish())
            if error is CancellationError {
                Self.log.notice("Clean cancelled: \(input.lastPathComponent)")
            } else {
                Self.log.error("Clean failed: \(input.lastPathComponent): \(error.localizedDescription)")
            }
            throw error
        }
    }

    /// Record whatever the engine wrote to stderr, line by line (so a multi-line
    /// Python traceback stays readable in the log). Empty in the normal case — the
    /// engine logs its own detail directly to the file.
    private static func logEngineStderr(_ lines: [String]) {
        for line in lines where !line.isEmpty {
            engineLog.error("[stderr] \(line)")
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
