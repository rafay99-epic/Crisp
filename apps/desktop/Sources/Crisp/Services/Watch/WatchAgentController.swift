import Foundation
import ServiceManagement
import CrispCore

/// Registers/unregisters the watch-folder background agent (the bundled
/// `CrispWatcher` LaunchAgent) via `SMAppService`. Registering makes it a login
/// item that runs even when the main window is closed; unregistering stops it.
/// The plist name is per-channel so the three installs each get their own agent.
@MainActor
@Observable
final class WatchAgentController {
    enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval     // user must allow it in System Settings ▸ Login Items
        case notFound
        case error(String)
    }

    private(set) var status: Status = .notRegistered

    /// `<bundle-id>.watcher.plist`, matching what build.sh writes into
    /// `Contents/Library/LaunchAgents/`.
    private var plistName: String {
        AppInfo.bundleIdentifier + Channel.current.bundleSuffix + ".watcher.plist"
    }

    private var service: SMAppService { SMAppService.agent(plistName: plistName) }

    /// Recompute status from the system (call on appear).
    func refresh() { status = map(service.status) }

    /// Turn the agent on or off. Returns false if the system rejected the change.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try service.register()
            } else {
                // Always attempt unregister when turning off — `status` can lag the
                // real BTM record, so don't gate on it (a no-op if truly absent).
                try service.unregister()
            }
            refresh()
            return true
        } catch {
            AppInfo.logger("watcher").error("SMAppService \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            return false
        }
    }

    private func map(_ status: SMAppService.Status) -> Status {
        switch status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered:    return .notRegistered
        case .notFound:         return .notFound
        @unknown default:       return .notRegistered
        }
    }
}
