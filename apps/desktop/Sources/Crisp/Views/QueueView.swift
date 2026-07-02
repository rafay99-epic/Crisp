import SwiftUI
import AppKit
import CrispCore

/// The clean queue — one row per video, with per-file status and progress. Waiting
/// rows can be reordered (top runs first), removed, and assigned a preset; running
/// and finished rows are fixed. Fills the window and scrolls on its own.
struct QueueView: View {
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings
    @Bindable var player: PreviewPlayer

    @State private var previewItem: QueueItem?
    @State private var reviewItem: QueueItem?
    // One editor-handoff picker for the whole queue (hosted here, not per-row) so a
    // batch of exports can't stack/lose sheets and List row recycling can't tear it down.
    // `editorPickerItem` is the prompt currently on screen; `pendingEditorItems` is a
    // FIFO of exports that finished while another sheet was up — a single slot would drop
    // them (batch concurrency > 1, or a Preview/Review sheet already open). We present one
    // at a time and drain the queue as each sheet dismisses.
    @State private var editorPickerItem: QueueItem?
    @State private var pendingEditorItems: [QueueItem] = []

    var body: some View {
        List {
            Section {
                ForEach($model.queue) { $item in
                    QueueRow(item: $item, model: model, player: player, presets: settings.presets,
                             onPreview: { previewItem = item },
                             onReview: { reviewItem = item },
                             onEditorPicker: { enqueueEditorPicker(item) })
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: model.moveWaiting)
            } header: {
                HStack {
                    Text("Queue")
                    Spacer()
                    Text(countLabel).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: countLabel)
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: model.queue.count)   // animate row insert/remove
        .sheet(item: $previewItem, onDismiss: presentNextEditorPicker) { item in
            PreviewSheet(item: item, model: model, settings: settings)
        }
        .sheet(item: $reviewItem, onDismiss: presentNextEditorPicker) { item in
            ReviewSheet(item: item, model: model, settings: settings)
        }
        .sheet(item: $editorPickerItem, onDismiss: presentNextEditorPicker) { item in
            EditorPickerSheet(editors: EditorDetector.installed(),
                              onOpen: { EditorDetector.openForImport($0, result: item.result) },
                              onReveal: { EditorDetector.revealProject(for: item.result) })
        }
    }

    /// Queue an editor-handoff prompt for `item` (dedup by id — a row's status can
    /// briefly re-fire `onChange`), then try to show it right away.
    private func enqueueEditorPicker(_ item: QueueItem) {
        guard editorPickerItem?.id != item.id,
              !pendingEditorItems.contains(where: { $0.id == item.id }) else { return }
        pendingEditorItems.append(item)
        presentNextEditorPicker()
    }

    /// Present the head of the FIFO — but only when no other sheet of this view is up
    /// (three sheets share one host; presenting over another silently fails). Hops to
    /// the next runloop so it never presents in the same update cycle as a dismissal,
    /// which SwiftUI also drops.
    private func presentNextEditorPicker() {
        DispatchQueue.main.async {
            guard editorPickerItem == nil, previewItem == nil, reviewItem == nil,
                  !pendingEditorItems.isEmpty else { return }
            editorPickerItem = pendingEditorItems.removeFirst()
        }
    }

    private var countLabel: String {
        let waiting = model.waitingCount
        let done = model.doneCount
        if model.isRunning { return "\(done) of \(model.queue.count) done" }
        if waiting == model.queue.count { return "\(waiting) video\(waiting == 1 ? "" : "s")" }
        return "\(done) done · \(waiting) waiting"
    }
}

/// One queued video. A status glyph that animates as the file moves through the
/// pipeline, the filename, a state-appropriate secondary line (preset picker while
/// waiting, progress while running, an honest "cut" bar once done), and a trailing
/// control (remove while waiting, reveal once done).
private struct QueueRow: View {
    @Binding var item: QueueItem
    let model: CleanModel
    let player: PreviewPlayer
    let presets: [Preset]
    let onPreview: () -> Void
    let onReview: () -> Void
    /// Ask the parent (QueueView) to show the editor-handoff picker for this row — one
    /// shared sheet, so batches and List recycling can't break it.
    let onEditorPicker: () -> Void

    /// The cleaned file, once it exists — used for drag-out, reveal, preview, copy.
    private var outputURL: URL? {
        guard let path = item.result?.output, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// True when this clean produced an editor project (a copy + .fcpxml timeline)
    /// instead of a rendered video — the result actions become "open/reveal project".
    private var editorExport: Bool { item.result?.exportTimeline == "fcpxml" }
    private var projectURL: URL? {
        guard let path = item.result?.projectDir, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
    private func revealProject() { EditorDetector.revealProject(for: item.result) }
    private func openInEditor(_ editor: VideoEditor) {
        EditorDetector.openForImport(editor, result: item.result)
    }

    var body: some View {
        Group {
            if item.status == .done, let url = outputURL {
                // Drag the result into Finder / an editor / an upload box. For an editor
                // handoff drag the whole project FOLDER (the .fcpxml alone would lose its
                // media references), with a matching label/icon.
                let dragURL = editorExport ? (projectURL ?? url) : url
                rowContent.draggable(dragURL) {
                    Label(editorExport ? "\(item.url.deletingPathExtension().lastPathComponent) (Crisp)"
                                       : item.url.lastPathComponent,
                          systemImage: editorExport ? "film.stack" : "scissors")
                }
            } else {
                rowContent
            }
        }
        .padding(.vertical, 3)
        .animation(.smooth, value: item.status)
        .contextMenu { contextMenu }
        // When an editor-handoff cut finishes, ask the parent to pop the (shared) picker
        // so the user just chooses where to open.
        .onChange(of: item.status) { _, status in
            if status == .done, editorExport { onEditorPicker() }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 11) {
            statusIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                secondaryLine
            }

            Spacer(minLength: 8)
            trailing
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .running:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: glyph)
                .font(.body)
                .foregroundStyle(glyphStyle)
                .symbolEffect(.bounce, value: item.status == .done)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder private var secondaryLine: some View {
        switch item.status {
        case .running:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: item.progress).controlSize(.small)
                if !item.stage.isEmpty {
                    Text(item.stage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        case .done:
            VStack(alignment: .leading, spacing: 3) {
                if let r = item.result, !r.peaks.isEmpty {
                    WaveformView(peaks: r.peaks, removed: r.removed)
                        .frame(height: 22)
                        .transition(.opacity)
                } else if let r = item.result, r.origSeconds > 0 {
                    ReductionBar(kept: max(0, min(1, r.newSeconds / r.origSeconds)))
                } else {
                    Text("Cleaned").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = item.result?.cutsSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
        case .waiting where !presets.isEmpty:
            Picker("Preset", selection: $item.presetID) {
                Text("Default").tag(UUID?.none)
                ForEach(presets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
        default:
            Text(detail)
                .font(.caption)
                .foregroundStyle(item.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch item.status {
        case .waiting:
            HStack(spacing: 10) {
                Button { onReview() } label: { Image(systemName: "slider.horizontal.below.rectangle") }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .help("Review & edit cuts")
                Button { onPreview() } label: { Image(systemName: "waveform") }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .help("Preview cuts")
                Button(role: .destructive) { model.remove(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove from queue")
            }
        case .running:
            Text("\(Int(item.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        case .done:
            // The saving, a preview toggle, and the reveal button — one grouped,
            // vertically-centered trailing cluster.
            HStack(spacing: 10) {
                if let r = item.result {
                    Text("removed \(formatTime(r.savedSeconds))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize()
                }
                // Editor handoff produced a project, not a video — open it in an editor
                // (a picker, in case more than one is installed) or reveal the project.
                if editorExport {
                    Button { onEditorPicker() } label: { Image(systemName: "film.stack") }
                        .buttonStyle(.plain).foregroundStyle(.tint)
                        .help("Open in a video editor")
                    Button { revealProject() } label: { Image(systemName: "folder") }
                        .buttonStyle(.plain).foregroundStyle(.tint)
                        .help("Show project in Finder")
                } else if let url = outputURL {
                    Button { player.toggle(url) } label: {
                        Image(systemName: player.isPlaying(url) ? "stop.circle.fill" : "play.circle")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .help(player.isPlaying(url) ? "Stop preview" : "Play preview")
                    Button { revealOutput() } label: { Image(systemName: "folder") }
                        .buttonStyle(.plain).foregroundStyle(.tint)
                        .help("Show in Finder")
                }
            }
            .transition(.scale.combined(with: .opacity))
        case .failed, .cancelled:
            Button { model.retry(item.id) } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .help("Try again")
        }
    }

    // MARK: - Context menu + actions

    @ViewBuilder private var contextMenu: some View {
        switch item.status {
        case .done:
            if let cuts = item.result?.cutsSummary { Text("Removed \(cuts)") }
            // Skip the file-size summary for an editor handoff — there's no rendered
            // video, so comparing the original to the tiny .fcpxml would mislead.
            if !editorExport, let summary = sizeSummary { Text(summary) }
            if editorExport {
                ForEach(EditorDetector.installed()) { editor in
                    Button { openInEditor(editor) } label: { Label("Open in \(editor.name)", systemImage: "film.stack") }
                }
                Button { revealProject() } label: { Label("Reveal Editor Project", systemImage: "folder") }
                Button { copyOutputPath() } label: { Label("Copy Timeline Path", systemImage: "doc.on.doc") }
            } else if let url = outputURL {
                Button { revealOutput() } label: { Label("Show in Finder", systemImage: "folder") }
                Button { copyOutputPath() } label: { Label("Copy Output Path", systemImage: "doc.on.doc") }
                Button { player.toggle(url) } label: {
                    Label(player.isPlaying(url) ? "Stop Preview" : "Play Preview",
                          systemImage: player.isPlaying(url) ? "stop.fill" : "play.fill")
                }
            }
            // The split-track stems, when the clean produced them (render mode only).
            if !editorExport, let video = stemURL(item.result?.videoOutput) {
                Button { reveal(video) } label: { Label("Show Video Track", systemImage: "film") }
            }
            if let audio = stemURL(item.result?.audioOutput) {
                Button { reveal(audio) } label: { Label("Show Audio Track", systemImage: "waveform") }
            }
            // The subtitle sidecars, when captions were exported.
            if let srt = stemURL(item.result?.srtOutput) {
                Button { reveal(srt) } label: { Label("Show Subtitles (.srt)", systemImage: "captions.bubble") }
            }
            if let vtt = stemURL(item.result?.vttOutput) {
                Button { reveal(vtt) } label: { Label("Show Subtitles (.vtt)", systemImage: "captions.bubble") }
            }
            // The backed-up pristine original, when one was kept.
            if let backup = item.result?.backup, !backup.isEmpty {
                Divider()
                BackupMenuItems(backupPath: backup, sourcePath: item.url.path)
            }
            Divider()
            Button { model.reclean(item.id) } label: { Label("Re-clean", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { model.remove(item.id) } label: {
                Label("Remove from Queue", systemImage: "trash")
            }
        case .failed, .cancelled:
            Button { model.retry(item.id) } label: { Label("Try Again", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { model.remove(item.id) } label: {
                Label("Remove from Queue", systemImage: "trash")
            }
        case .waiting:
            Button { onReview() } label: {
                Label("Review & Edit Cuts\u{2026}", systemImage: "slider.horizontal.below.rectangle")
            }
            Button { onPreview() } label: { Label("Preview Cuts\u{2026}", systemImage: "waveform") }
            Button(role: .destructive) { model.remove(item.id) } label: {
                Label("Remove from Queue", systemImage: "trash")
            }
        case .running:
            EmptyView()
        }
    }

    private func stemURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func revealOutput() {
        if let url = outputURL { reveal(url) }
    }

    private func copyOutputPath() {
        guard let url = outputURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// Input → output file size with the percentage shrink, shown as an info line in
    /// the menu. Computed on demand (only when the menu opens).
    private var sizeSummary: String? {
        guard let out = outputURL,
              let outSize = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size]) as? Int64
        else { return nil }
        let outStr = ByteCountFormatter.string(fromByteCount: outSize, countStyle: .file)
        if let inSize = (try? FileManager.default.attributesOfItem(atPath: item.url.path)[.size]) as? Int64,
           inSize > 0 {
            let inStr = ByteCountFormatter.string(fromByteCount: inSize, countStyle: .file)
            let pct = Int((1 - Double(outSize) / Double(inSize)) * 100)
            return pct > 0 ? "\(inStr) → \(outStr) · \(pct)% smaller" : "\(inStr) → \(outStr)"
        }
        return outStr
    }

    // `glyph` is only consulted for non-running rows (running shows a spinner).
    private var glyph: String {
        switch item.status {
        case .done:      return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .cancelled: return "minus.circle"
        default:         return "circle.dotted"   // waiting
        }
    }

    private var glyphStyle: AnyShapeStyle {
        switch item.status {
        case .done:    return AnyShapeStyle(.green)
        case .failed:  return AnyShapeStyle(.red)
        default:       return AnyShapeStyle(.secondary)
        }
    }

    // Only reached for the non-waveform secondary states (waiting w/o presets,
    // canceled, failed); running/done render their own views.
    private var detail: String {
        switch item.status {
        case .cancelled: return "Canceled"
        case .failed:    return item.error ?? "Couldn\u{2019}t be cleaned"
        default:         return "Waiting"
        }
    }
}

/// A tiny honest "cut" bar: how much of the original survived (filled, in the row's
/// accent) versus what was removed (the dim track behind it). Built straight from
/// the result's durations — it shows exactly what Crisp took out. Fallback for when
/// the waveform summary isn't available.
private struct ReductionBar: View {
    let kept: Double   // 0…1 of the original duration that remains

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green).frame(width: proxy.size.width * kept)
            }
        }
        .frame(width: 64, height: 4)
        .help("Kept \(Int(kept * 100))% of the original")
    }
}
