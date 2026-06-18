import Foundation

/// Decides how many videos Crisp may clean at once, from a `SystemSnapshot` and the
/// user's settings. Pure (no I/O) so it's unit-testable with synthetic snapshots.
///
/// Every clean is expensive (decode → silence detect → whisper transcription →
/// re-encode), so running several at once contends for RAM, CPU, and the shared
/// media engine. The governor takes the **minimum** of a few caps and never returns
/// less than 1 (serial is always safe — it's today's behavior).
public enum ResourceGovernor {
    /// RAM kept aside for the OS and the app itself, never handed to clean jobs.
    public static let systemReserveBytes: UInt64 = 2 * 1024 * 1024 * 1024
    /// P-cores assumed busy per concurrent clean (whisper + ffmpeg are threaded).
    public static let coresPerJob = 2
    /// Concurrent hardware encodes the shared VideoToolbox media engine sustains.
    public static let mediaEngineCap = 3

    public struct Verdict: Sendable, Equatable {
        /// Whether the requested concurrency fits in current free resources.
        public var fits: Bool
        /// Bytes the request needs (requested × per-job budget + reserve).
        public var neededBytes: UInt64
        /// Bytes currently available.
        public var availableBytes: UInt64
        /// True when heat — not memory — is the blocker.
        public var thermalBlocked: Bool
    }

    private static func perJobBytes(_ config: EngineConfig) -> UInt64 {
        UInt64(max(256, config.perJobMemoryBudgetMB)) * 1024 * 1024
    }

    private static func cpuCap(_ snapshot: SystemSnapshot) -> Int {
        max(1, snapshot.performanceCoreCount / coresPerJob)
    }

    private static func mediaCap(_ config: EngineConfig) -> Int {
        // Software encoding is CPU-bound (no media-engine contention), so only the
        // CPU cap applies; hardware encoding shares the one media engine.
        config.hardwareEncoding ? mediaEngineCap : Int.max
    }

    private static func memoryCap(forBytes bytes: UInt64, _ config: EngineConfig) -> Int {
        guard bytes > systemReserveBytes else { return 1 }
        return max(1, Int((bytes - systemReserveBytes) / perJobBytes(config)))
    }

    private static func thermalOK(_ snapshot: SystemSnapshot) -> Bool {
        snapshot.thermalState != .serious && snapshot.thermalState != .critical
    }

    /// The machine's theoretical maximum — capped by total RAM, P-cores, and the
    /// media engine, ignoring what's free right now. The target for Ultra and the
    /// upper bound for the Manual stepper.
    public static func hardwareCeiling(snapshot: SystemSnapshot, config: EngineConfig) -> Int {
        max(1, min(memoryCap(forBytes: snapshot.physicalMemory, config),
                   cpuCap(snapshot), mediaCap(config)))
    }

    /// A safe count for **right now** — capped by *available* memory and throttled to
    /// 1 under thermal pressure. This is the Automatic value, and it fits by
    /// construction (no preflight needed).
    public static func recommended(snapshot: SystemSnapshot, config: EngineConfig) -> Int {
        guard thermalOK(snapshot) else { return 1 }
        return max(1, min(memoryCap(forBytes: snapshot.availableMemory, config),
                          cpuCap(snapshot), mediaCap(config)))
    }

    /// The concurrency to actually use for a given mode.
    public static func plannedConcurrency(mode: ConcurrencyMode,
                                          snapshot: SystemSnapshot, config: EngineConfig) -> Int {
        switch mode {
        case .auto:
            return recommended(snapshot: snapshot, config: config)
        case .manual:
            return min(max(1, config.manualConcurrency),
                       hardwareCeiling(snapshot: snapshot, config: config))
        case .ultra:
            return hardwareCeiling(snapshot: snapshot, config: config)
        }
    }

    /// Whether `requested` concurrent cleans fit in current free resources. Used by
    /// Ultra to hard-block (and re-check) before starting.
    public static func preflight(requested: Int, snapshot: SystemSnapshot,
                                 config: EngineConfig) -> Verdict {
        let needed = UInt64(max(1, requested)) * perJobBytes(config) + systemReserveBytes
        let hot = !thermalOK(snapshot)
        return Verdict(fits: !hot && snapshot.availableMemory >= needed,
                       neededBytes: needed,
                       availableBytes: snapshot.availableMemory,
                       thermalBlocked: hot)
    }
}
