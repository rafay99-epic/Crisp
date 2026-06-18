import Foundation
import Darwin

/// A point-in-time read of the machine's resources, used by `ResourceGovernor` to
/// decide how many cleans can run at once. A plain value so the governor's logic is
/// pure and unit-testable with synthetic snapshots.
public struct SystemSnapshot: Sendable, Equatable {
    /// Total installed RAM, in bytes.
    public var physicalMemory: UInt64
    /// Memory that could be made available without swapping, in bytes (free +
    /// inactive + purgeable + speculative pages).
    public var availableMemory: UInt64
    /// Number of performance ("P") cores — the cores that matter for encode/whisper.
    public var performanceCoreCount: Int
    /// Current thermal pressure; `serious`/`critical` forces serial cleaning.
    public var thermalState: ProcessInfo.ThermalState

    public init(physicalMemory: UInt64, availableMemory: UInt64,
                performanceCoreCount: Int,
                thermalState: ProcessInfo.ThermalState) {
        self.physicalMemory = physicalMemory
        self.availableMemory = availableMemory
        self.performanceCoreCount = performanceCoreCount
        self.thermalState = thermalState
    }
}

/// Gathers a `SystemSnapshot` from public macOS APIs only — `ProcessInfo`, a mach
/// `host_statistics64` VM read, and a `sysctl` for the P-core count. No private
/// GPU/media-engine metering (macOS exposes none cleanly), so the governor reasons
/// about RAM + CPU + thermal and treats the media engine as a fixed contention cap.
public enum SystemProbe {
    public static func snapshot() -> SystemSnapshot {
        let info = ProcessInfo.processInfo
        let physical = info.physicalMemory
        // If the mach read fails, fall back to a conservative half of RAM rather
        // than 0 — 0 would wedge Ultra's preflight (it could never pass).
        let available = availableMemory() ?? (physical / 2)
        return SystemSnapshot(
            physicalMemory: physical,
            availableMemory: available,
            performanceCoreCount: performanceCoreCount(),
            thermalState: info.thermalState)
    }

    /// Free + inactive + purgeable + speculative pages — memory the OS can hand out
    /// without pushing other apps to swap. `nil` if the mach call fails.
    private static func availableMemory() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_page_size)
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count)
            + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
        return pages * pageSize
    }

    /// P-core count via `hw.perflevel0.logicalcpu` (Apple Silicon's highest-perf
    /// level; P-cores aren't hyperthreaded so logical == physical). Falls back to
    /// the total logical core count if the sysctl is unavailable.
    private static func performanceCoreCount() -> Int {
        sysctlInt("hw.perflevel0.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
