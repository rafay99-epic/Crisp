import SwiftUI
import AppKit
import CrispCore

/// The pinned bar along the bottom of the working layout. It always holds the
/// primary action (so it's reachable no matter how long the queue is) plus, when
/// idle, the default recipe for new files; while running, the overall progress;
/// when finished, a one-line summary. Native `.bar` material, like Mail/Finder.
struct BottomBar: View {
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings
    /// Fillers need the speech model; true while it's missing/downloading.
    let modelBlocks: Bool
    let onStart: () -> Void

    private var pending: Int { model.queue.filter { $0.isWaiting }.count }
    private var doneCount: Int { model.queue.filter { $0.status == .done }.count }

    var body: some View {
        HStack(spacing: 14) {
            leading
            Spacer(minLength: 12)
            action
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.smooth, value: model.isRunning)
        .animation(.smooth, value: pending)
        .animation(.smooth, value: model.results.count)
    }

    // MARK: - Leading (recipe / progress / summary)

    @ViewBuilder private var leading: some View {
        if model.isRunning {
            HStack(spacing: 10) {
                ProgressView(value: model.overallProgress).frame(width: 170)
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if pending > 0 {
            // There's something to clean → show the default recipe + a hint line.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Cut").font(.callout).foregroundStyle(.secondary).fixedSize()
                        Picker("Cut", selection: $model.strength) {
                            ForEach(Strength.allCases) { Text($0.pickerLabel).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    Toggle("Remove fillers", isOn: $model.removeFillers)
                        .toggleStyle(.checkbox)
                }
                .fixedSize()        // keep the whole recipe row on one line
                caption
            }
        } else {
            // Nothing left to clean → just the summary, leaving room for the
            // Clear / Show in Finder actions on the right (fits a narrow window).
            caption
        }
    }

    @ViewBuilder private var caption: some View {
        if model.errorMessage != nil, doneCount == 0 {
            Label(model.errorMessage ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(1)
        } else if !model.results.isEmpty {
            Label("Cleaned \(doneCount) \u{00B7} removed \(formatTime(totalSaved)) total",
                  systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green).lineLimit(1).fixedSize()
        } else if settings.backupOriginal {
            Label("Originals are backed up", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        } else {
            Text("Crisp only writes a cleaned copy \u{2014} your originals are untouched.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var totalSaved: Double { model.results.reduce(0) { $0 + $1.savedSeconds } }

    // MARK: - Trailing action

    @ViewBuilder private var action: some View {
        if model.isRunning {
            Button(role: .cancel) { model.cancel() } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
            }
            .controlSize(.large).tint(.red)
            .keyboardShortcut(.cancelAction)
        } else if pending > 0 {
            Button(action: onStart) {
                Label(pending == 1 ? "Clean Video" : "Clean \(pending) Videos", systemImage: "scissors")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(modelBlocks)
            .keyboardShortcut(.return, modifiers: .command)
        } else if !model.results.isEmpty {
            Button { model.reset() } label: { Text("Clear") }
                .controlSize(.large)
            Button {
                if let path = model.results.last?.output {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            } label: { Label("Show in Finder", systemImage: "folder") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}
