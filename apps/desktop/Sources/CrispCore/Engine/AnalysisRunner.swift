import Foundation

/// The audio analysis behind the live cut preview: the engine's analyze-only mode
/// (extract audio → find candidate silences → waveform peaks; no transcription, no
/// render). Fast, and computed once — the app then recomputes cut regions locally
/// from `silences` as the user drags the knobs (see `CutPreview`), re-analyzing only
/// if the silence floor changes.
public struct VideoAnalysis: Sendable {
    public let duration: Double
    public let peaks: [Double]
    /// Raw candidate silence intervals `(start, end)` in seconds.
    public let silences: [(Double, Double)]
}

public struct AnalysisRunner {
    private static let engineLog = AppInfo.logger("engine")

    public init() {}

    private struct AnalysisEvent: Decodable {
        let event: String
        var message: String?
        var duration: Double?
        var peaks: [Double]?
        var silences: [[Double]]?
    }

    /// Run `clean_video.py --analyze` for one file at the given silence floor.
    /// Honors task cancellation (terminates the subprocess).
    public func analyze(input: URL, noiseDB: Double, buckets: Int = 240) async throws -> VideoAnalysis {
        let script = try CleanEngine.scriptURL()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CleanEngine.python)
        proc.arguments = [script.path, input.path, "--analyze",
                          "--noise", String(noiseDB),
                          "--waveform", String(buckets), "--ndjson"]
        proc.environment = CleanEngine.environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Drain stderr via a readabilityHandler, not a second `bytes.lines`: two
        // concurrent FileHandle.AsyncBytes readers contend on a shared serial queue,
        // so a stderr reader blocked on an empty pipe stalls the stdout reader until
        // EOF (see StderrDrain). Same safety net (drains a flood promptly), without
        // starving the stdout stream.
        let stderrDrain = StderrDrain(errPipe.fileHandleForReading)

        do {
            let analysis = try await withTaskCancellationHandler { () throws -> VideoAnalysis in
                // Already cancelled before the handler installed: don't launch at all.
                if Task.isCancelled {
                    try? errPipe.fileHandleForWriting.close()
                    throw CancellationError()
                }
                do {
                    try proc.run()
                } catch {
                    // The child never started — close our write end so the drain task
                    // hits EOF and returns instead of hanging.
                    try? errPipe.fileHandleForWriting.close()
                    throw error
                }
                var analysis: VideoAnalysis?
                let decoder = JSONDecoder()
                for try await line in outPipe.fileHandleForReading.bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8),
                          let ev = try? decoder.decode(AnalysisEvent.self, from: data) else { continue }
                    switch ev.event {
                    case "analysis":
                        analysis = VideoAnalysis(
                            duration: ev.duration ?? 0,
                            peaks: ev.peaks ?? [],
                            silences: (ev.silences ?? []).compactMap {
                                $0.count == 2 ? ($0[0], $0[1]) : nil
                            })
                    case "error":
                        throw NSError(domain: "Crisp", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: ev.message ?? "Analysis failed"])
                    default:
                        break
                    }
                }
                proc.waitUntilExit()
                if Task.isCancelled { throw CancellationError() }
                guard let analysis else {
                    throw NSError(domain: "Crisp", code: 2, userInfo:
                        [NSLocalizedDescriptionKey: "Couldn't analyze this video."])
                }
                return analysis
            } onCancel: {
                // Only a launched process can be terminated. If the task is already
                // cancelled when `withTaskCancellationHandler` installs this handler,
                // it runs *immediately* — before `proc.run()` — and `terminate()` on an
                // unlaunched NSTask throws NSInvalidArgumentException ("task not
                // launched"), an uncaught ObjC exception that crashes the app.
                if proc.isRunning { proc.terminate() }
            }
            Self.logStderr(stderrDrain.finish())
            return analysis
        } catch {
            Self.logStderr(stderrDrain.finish())
            throw error
        }
    }

    private static func logStderr(_ lines: [String]) {
        for line in lines where !line.isEmpty {
            engineLog.error("[analyze stderr] \(line)")
        }
    }
}
