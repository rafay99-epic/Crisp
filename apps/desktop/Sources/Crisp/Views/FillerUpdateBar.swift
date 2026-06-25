import SwiftUI

/// A small bar in the main window when a newer filler model is available — the model
/// counterpart to `UpdateBanner` (which is for app updates). Same look + placement.
struct FillerUpdateBar: View {
    @Bindable var updater: FillerModelUpdater
    @Bindable var store: ModelStore

    var body: some View {
        if case .available(let version) = updater.state {
            HStack(spacing: 10) {
                Image(systemName: "bird.fill").foregroundStyle(.tint)
                Text("Filler model update available — v\(version)")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Update") { Task { await updater.apply(using: store) } }
                    .controlSize(.small)
                    .disabled(store.state.isBusy)
                Button { updater.clear() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Dismiss")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .cardBackground(.tint.opacity(0.12), cornerRadius: 12)
        }
    }
}
