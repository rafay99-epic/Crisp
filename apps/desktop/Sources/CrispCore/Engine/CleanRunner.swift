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

        proc.environment = CleanEngine.environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        Self.log.info("Clean start: \(input.lastPathComponent) [\(parameters.videoCodec)/\(parameters.audioCodec) q=\(parameters.videoQuality) hw=\(parameters.hardwareEncoding) fillers=\(options.removeFillers)]")

        // Drain the engine's own stderr in the background so a flood (e.g. a Python
        // traceback) can't deadlock the stdout reader by filling the pipe buffer.
        // This is the safety net for failures that escape before the engine can emit
        // a structured error — the bundled engine routes its detail to the log file,
        // so anything here means something went wrong unexpectedly. Uses the async
        // byte stream (not a blocking `readToEnd`) so it suspends rather than tying
        // up a cooperative-pool thread — important when several cleans run at once.
        // Bounded to the most recent lines so a pathological spew can't grow memory
        // without limit; for a traceback the root cause is at the end anyway.
        let maxStderrLines = 500
        let stderrTask = Task<[String], Never> {
            var lines: [String] = []
            do {
                for try await line in errPipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    // Trim in batches (drop oldest) so this stays amortized O(1).
                    if lines.count > maxStderrLines * 2 {
                        lines.removeFirst(lines.count - maxStderrLines)
                    }
                }
            } catch {
                // Best-effort: the clean's own result/error is what actually matters.
            }
            if lines.count > maxStderrLines {
                lines.removeFirst(lines.count - maxStderrLines)
            }
            return lines
        }

        do {
            let result = try await withTaskCancellationHandler {
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
                proc.terminate()
            }
            Self.logEngineStderr(await stderrTask.value)
            Self.log.info("Clean done: \(input.lastPathComponent) → \(URL(fileURLWithPath: result.output).lastPathComponent) (saved \(Int(result.savedSeconds))s, \(result.fillers) fillers, \(result.pauses) pauses)")
            // Record to History from this shared path, so the queue, watch-folder
            // agent, App Intent, and menu-bar drop all land in one timeline.
            if !result.output.isEmpty {
                HistoryStore.shared.record(HistoryEntry(input: input, result: result, date: Date()))
            }
            return result
        } catch {
            Self.logEngineStderr(await stderrTask.value)
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
