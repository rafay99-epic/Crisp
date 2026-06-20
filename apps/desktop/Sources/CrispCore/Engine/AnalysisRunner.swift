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

        // Drain stderr concurrently (bounded) so a flood can't deadlock the stdout
        // reader by filling the pipe buffer — same safety net as CleanRunner. The
        // engine routes its detail to the log file, so anything here is unexpected.
        let stderrTask = Task<[String], Never> {
            var lines: [String] = []
            do {
                for try await line in errPipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    if lines.count > 400 { lines.removeFirst(lines.count - 200) }
                }
            } catch { /* best-effort */ }
            return lines
        }

        do {
            let analysis = try await withTaskCancellationHandler { () throws -> VideoAnalysis in
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
            Self.logStderr(await stderrTask.value)
            return analysis
        } catch {
            Self.logStderr(await stderrTask.value)
            throw error
        }
    }

    private static func logStderr(_ lines: [String]) {
        for line in lines where !line.isEmpty {
            engineLog.error("[analyze stderr] \(line)")
        }
    }
}
