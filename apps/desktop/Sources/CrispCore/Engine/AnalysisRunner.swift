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
        proc.standardOutput = outPipe
        proc.standardError = Pipe()   // detail goes to the engine log file

        return try await withTaskCancellationHandler {
            try proc.run()
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
            proc.terminate()
        }
    }
}
