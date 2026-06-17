import SwiftUI

/// Shows an "update available" bar and an install button when the updater finds
/// a newer build for this channel.
struct UpdateBanner: View {
    @Bindable var updater: Updater

    var body: some View {
        if case .available(let release) = updater.status {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("Update available — \(release.displayVersion)")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Install & Relaunch") { Task { await updater.downloadAndInstall() } }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .cardBackground(.tint.opacity(0.12), cornerRadius: 12)
        } else if updater.status == .downloading || updater.status == .installing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(updater.status == .downloading ? "Downloading update\u{2026}" : "Installing update\u{2026}")
                    .font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .cardBackground(.quaternary.opacity(0.3), cornerRadius: 12)
        }
    }
}
