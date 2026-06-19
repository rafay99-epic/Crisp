import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CrispCore

/// The menu-bar quick-drop popover: drop (or choose) a video to clean it with the
/// default recipe without opening the main window. Shows live status and a reveal
/// for the last result, plus a way back into the full app.
struct MenuBarPanel: View {
    @Bindable var quickDrop: QuickDropModel
    @Bindable var settings: EngineSettings
    @Environment(\.openWindow) private var openWindow

    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                Text("Quick Clean").font(.headline)
            }

            dropZone
            statusLine

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open \(Channel.current.displayName)", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: targeted)
            Text("Drop a video to clean")
                .font(.callout).foregroundStyle(.secondary)
            Button("Choose Video\u{2026}") { chooseFile() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
        )
        .dropDestination(for: URL.self) { urls, _ in
            quickDrop.enqueue(urls, settings: settings)
        } isTargeted: { targeted = $0 }
    }

    // MARK: - Status

    @ViewBuilder private var statusLine: some View {
        switch quickDrop.state {
        case .idle:
            Text("Uses your default recipe.")
                .font(.caption).foregroundStyle(.secondary)
        case .preparing(let name):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing \(name)\u{2026}").font(.caption).lineLimit(1).truncationMode(.middle)
            }
        case .cleaning(let name, let remaining):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cleaning \(name)").font(.caption).lineLimit(1).truncationMode(.middle)
                    if remaining > 0 {
                        Text("\(remaining) more queued").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        case .done(let output, let saved, let cleaned, let failed):
            VStack(alignment: .leading, spacing: 4) {
                if let output {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    } label: {
                        Label("Cleaned \(cleaned) \u{00B7} removed \(formatTime(saved)) \u{2014} show in Finder",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green).lineLimit(2)
                    }
                    .buttonStyle(.plain)
                }
                if failed > 0 {
                    Label(failed == 1 ? "1 couldn\u{2019}t be cleaned" : "\(failed) couldn\u{2019}t be cleaned",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    // MARK: - File picker

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose a video to clean with your default recipe."
        if panel.runModal() == .OK {
            quickDrop.enqueue(panel.urls, settings: settings)
        }
    }
}
