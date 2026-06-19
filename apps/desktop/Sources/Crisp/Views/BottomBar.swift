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
    @Bindable var estimate: EstimateModel
    /// Fillers need the speech model; true while it's missing/downloading.
    let modelBlocks: Bool
    let onStart: () -> Void
    let onEstimate: () -> Void

    private var pending: Int { model.waitingCount }
    private var doneCount: Int { model.doneCount }

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
                estimateRow
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
            Label(summaryText, systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green).lineLimit(1)
        } else if settings.backupOriginal {
            Label("Originals are backed up", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        } else {
            Text("Crisp only writes a cleaned copy \u{2014} your originals are untouched.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Pre-flight estimate: a button to predict the time saved before cleaning, or
    /// its progress / result once run.
    @ViewBuilder private var estimateRow: some View {
        switch estimate.state {
        case .idle:
            Button("Estimate savings", action: onEstimate)
                .buttonStyle(.link).controlSize(.small)
        case .estimating(let done, let total):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Estimating\u{2026} \(done)/\(total)").font(.caption).foregroundStyle(.secondary)
            }
        case .done(let removed, let orig, let partial):
            let pct = orig > 0 ? Int((removed / orig) * 100) : 0
            Text("\u{2248} \(formatTime(removed)) would be removed (\(pct)% shorter)"
                 + (partial ? " \u{00B7} some files couldn\u{2019}t be read" : "")
                 + " \u{00B7} pauses only")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .failed:
            Text("Couldn\u{2019}t estimate those videos.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var totalSaved: Double { model.results.reduce(0) { $0 + $1.savedSeconds } }

    /// "Cleaned 3 · saved 3:21 · 12 fillers · 47 pauses" — count and time-saved come
    /// first so the cut totals (added last) are what truncates in a narrow window,
    /// not the headline figure.
    private var summaryText: String {
        let fillers = model.results.reduce(0) { $0 + $1.fillers }
        let pauses = model.results.reduce(0) { $0 + $1.pauses }
        var line = "Cleaned \(doneCount) \u{00B7} saved \(formatTime(totalSaved))"
        if let cuts = CleanResult.cutsSummary(fillers: fillers, pauses: pauses) {
            line += " \u{00B7} \(cuts)"
        }
        return line
    }

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
                // Reveal every cleaned file, not just one — they may span folders.
                let urls = model.results.filter { !$0.output.isEmpty }
                    .map { URL(fileURLWithPath: $0.output) }
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            } label: { Label("Show in Finder", systemImage: "folder") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}
