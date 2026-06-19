import SwiftUI
import AppKit
import CrispCore

/// The History window: every past clean (from the queue, the watch folder, the App
/// Intent, and the menu-bar drop) with its stats, plus quick reveal / re-clean. Reads
/// the append-only `history.jsonl` via `HistoryStore`.
struct HistoryView: View {
    @Bindable var model: CleanModel
    @Environment(\.openWindow) private var openWindow

    @State private var entries: [HistoryEntry] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                List(entries) { entry in
                    HistoryRow(entry: entry,
                               onReveal: { reveal(entry) },
                               onCleanAgain: sourceExists(entry) ? { cleanAgain(entry) } : nil)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh")
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) { clearHistory() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear history")
                .disabled(entries.isEmpty)
            }
        }
        .onAppear(perform: reload)
        // Refresh when a clean finishes while the window is open.
        .onChange(of: model.doneCount) { reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No cleans yet").font(.headline)
            Text("Cleaned videos will appear here \u{2014} from the queue, the watch folder, Shortcuts, and the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Actions

    private func reload() { entries = HistoryStore.shared.load() }

    private func clearHistory() {
        HistoryStore.shared.clear()
        entries = []
    }

    private func sourceExists(_ entry: HistoryEntry) -> Bool {
        FileManager.default.fileExists(atPath: entry.inputPath)
    }

    private func reveal(_ entry: HistoryEntry) {
        if let out = entry.outputURL, FileManager.default.fileExists(atPath: out.path) {
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } else if sourceExists(entry) {
            NSWorkspace.shared.activateFileViewerSelecting([entry.inputURL])
        }
    }

    private func cleanAgain(_ entry: HistoryEntry) {
        guard sourceExists(entry) else { return }
        model.addFiles([entry.inputURL])
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One row in the History list.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let onReveal: () -> Void
    let onCleanAgain: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.inputName)
                    .font(.callout).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onReveal) { Image(systemName: "folder") }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .help("Show in Finder")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button { onReveal() } label: { Label("Show in Finder", systemImage: "folder") }
            if let onCleanAgain {
                Button { onCleanAgain() } label: { Label("Clean Again", systemImage: "arrow.clockwise") }
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.outputURL?.path ?? entry.inputPath, forType: .string)
            } label: { Label("Copy Output Path", systemImage: "doc.on.doc") }
        }
    }

    /// "yesterday · saved 3:21 · 12 fillers · 47 pauses"
    private var subtitle: String {
        var parts = [entry.date.formatted(.relative(presentation: .named)),
                     "saved \(formatTime(entry.savedSeconds))"]
        if let cuts = entry.cutsSummary { parts.append(cuts) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
