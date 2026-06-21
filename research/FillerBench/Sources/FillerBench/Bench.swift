import Foundation
import Observation

struct BenchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Drives the Python report script and publishes the decoded result.
/// Mirrors how the main Crisp app drives its engine: spawn a subprocess, read
/// its JSON, keep the UI a pure display layer.
@MainActor @Observable
final class Bench {
    /// Portable default: $CRISP_RESEARCH_DIR, else `<cwd>/research` if it exists,
    /// else the cwd. Editable in the UI — no machine-specific path hardcoded.
    static let defaultResearchDir: String = {
        if let env = ProcessInfo.processInfo.environment["CRISP_RESEARCH_DIR"] { return env }
        let cwd = FileManager.default.currentDirectoryPath
        let nested = cwd + "/research"
        return FileManager.default.fileExists(atPath: nested) ? nested : cwd
    }()

    var researchDir = Bench.defaultResearchDir
    var split = "test"
    var quick = false            // pass --limit for fast feedback while iterating
    var report: Report?
    var errorText: String?
    var isRunning = false

    func run() {
        guard !isRunning else { return }
        isRunning = true
        errorText = nil
        let dir = researchDir, split = self.split, quick = self.quick
        Task.detached(priority: .userInitiated) {
            let result = Self.execute(dir: dir, split: split, quick: quick)
            await MainActor.run {
                switch result {
                case .success(let r): self.report = r
                case .failure(let err): self.errorText = err.message
                }
                self.isRunning = false
            }
        }
    }

    nonisolated private static func execute(dir: String, split: String, quick: Bool) -> Result<Report, BenchError> {
        let python = dir + "/.venv/bin/python"
        guard FileManager.default.isExecutableFile(atPath: python) else {
            return .failure(BenchError(message: "No venv python at \(python). Set the research dir to the folder containing .venv/."))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        var args = ["-m", "filler_classifier.report", "--data", "data/PodcastFillers", "--split", split]
        if quick { args += ["--limit", "400"] }
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            return .failure(BenchError(message: "Failed to launch python: \(error.localizedDescription)"))
        }

        // Drain stderr concurrently: torch can print warnings there, and reading
        // the two pipes sequentially would deadlock if stderr fills its buffer
        // before stdout closes.
        var errData = Data()
        let errHandle = err.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errHandle.readDataToEndOfFile()
            group.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            return .failure(BenchError(message: stderr.isEmpty ? "python exited \(proc.terminationStatus)" : stderr))
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return .success(try decoder.decode(Report.self, from: data))
        } catch {
            return .failure(BenchError(message: "Could not parse report JSON: \(error)"))
        }
    }
}
