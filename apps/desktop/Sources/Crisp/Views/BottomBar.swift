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
    /// Repeated-take removal needs the speech model to transcribe, which the fast
    /// on-device filler model can't — so the toggle is unavailable only when that model
    /// is the *active* backend (filler removal on and the model enabled). With fillers
    /// off, whisper runs and retakes are available again. Matches `CleanModel.start`.
    private var retakesUnavailable: Bool {
        model.removeFillers && settings.fillerModelEnabled
    }

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
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Cut").font(.callout).foregroundStyle(.secondary).fixedSize()
                        Picker("Cut", selection: $model.strength) {
                            ForEach(Strength.allCases) { Text($0.pickerLabel).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    // One "Remove" label shared by both toggles — compact, and avoids
                    // repeating the verb (keeps the bar on one line in a narrow window).
                    HStack(spacing: 10) {
                        Text("Remove").font(.callout).foregroundStyle(.secondary).fixedSize()
                        Toggle("Fillers", isOn: $model.removeFillers)
                            .toggleStyle(.checkbox)
                        // Retake removal needs the speech model to transcribe, which the
                        // fast on-device filler model can't do — so it's unavailable while
                        // that model is on (mirrors how captions are disabled), shown off
                        // and greyed rather than silently falling back to whisper.
                        Toggle("Repeated takes", isOn: Binding(
                            get: { model.removeRetakes && !retakesUnavailable },
                            set: { model.removeRetakes = $0 }))
                            .toggleStyle(.checkbox)
                            .disabled(retakesUnavailable)
                            .help(retakesUnavailable
                                  ? "Unavailable with the fast on-device filler model — finding repeated takes needs the speech model to transcribe. Turn the fast model off in Settings to use this."
                                  : "Remove a phrase you flubbed and immediately said again, keeping the corrected take.")
                    }
                }
                .fixedSize()        // keep the whole recipe row on one line
                if retakesUnavailable { retakeUnavailableNote }
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

    /// Visible reason the "Repeated takes" toggle is greyed out (a tooltip alone
    /// isn't discoverable): the fast filler model can't transcribe, so it can't find
    /// retakes — point the user to the more powerful speech model.
    @ViewBuilder private var retakeUnavailableNote: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small).foregroundStyle(.orange)
            Text("The fast filler model can't find repeated takes.")
            SettingsLink { Text("Switch in Settings") }
                .buttonStyle(.link)
        }
        .font(.caption).foregroundStyle(.secondary).fixedSize()
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
        case .done(let removed, let orig, let pauseCount, let partial):
            let pct = orig > 0 ? Int((removed / orig) * 100) : 0
            // The estimate is a fast, no-transcription pass, so it can count pauses but
            // not fillers/retakes (those need whisper) — say where those are counted.
            Text("\u{2248} \(formatTime(removed)) \u{00B7} \(pauseCount) pause\(pauseCount == 1 ? "" : "s") (\(pct)% shorter)"
                 + (partial ? " \u{00B7} some files couldn\u{2019}t be read" : "")
                 + " \u{00B7} fillers & repeated takes counted while cleaning")
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
        let retakes = model.results.reduce(0) { $0 + $1.retakes }
        var line = "Cleaned \(doneCount) \u{00B7} saved \(formatTime(totalSaved))"
        if let cuts = CleanResult.cutsSummary(fillers: fillers, pauses: pauses, retakes: retakes) {
            line += " \u{00B7} \(cuts)"
        }
        return line
    }

    // MARK: - Trailing action

    /// The primary-button title. With editor handoff on, the cut produces an editor
    /// timeline (no render), so the button says "Prepare for Editor".
    private var startTitle: String {
        if settings.exportToEditor {
            return pending == 1 ? "Prepare for Editor" : "Prepare \(pending) for Editor"
        }
        return pending == 1 ? "Clean Video" : "Clean \(pending) Videos"
    }

    @ViewBuilder private var action: some View {
        if model.isRunning {
            Button(role: .cancel) { model.cancel() } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
            }
            .controlSize(.large).tint(.red).fixedSize()
            .keyboardShortcut(.cancelAction)
        } else if pending > 0 {
            Button(action: onStart) {
                Label(startTitle, systemImage: settings.exportToEditor ? "film.stack" : "scissors")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .fixedSize()        // always show the full label — never clip to "Cle…"
            .disabled(modelBlocks)
            .keyboardShortcut(.return, modifiers: .command)
        } else if !model.results.isEmpty {
            Button { model.reset() } label: { Text("Clear") }
                .controlSize(.large).fixedSize()
            Button {
                // Reveal every cleaned file, not just one — they may span folders.
                let urls = model.results.filter { !$0.output.isEmpty }
                    .map { URL(fileURLWithPath: $0.output) }
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            } label: { Label("Show in Finder", systemImage: "folder") }
            .buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
        }
    }
}
