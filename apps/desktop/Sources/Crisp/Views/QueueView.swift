import SwiftUI
import AppKit
import CrispCore

/// The clean queue — one row per video, with per-file status and progress. Waiting
/// rows can be reordered (top runs first), removed, and assigned a preset; running
/// and finished rows are fixed. Fills the window and scrolls on its own.
struct QueueView: View {
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings

    var body: some View {
        List {
            Section {
                ForEach($model.queue) { $item in
                    QueueRow(item: $item, presets: settings.presets,
                             defaultName: settings.defaultPreset?.name,
                             onRemove: { model.remove(item.id) })
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
    }

    private var countLabel: String {
        let waiting = model.queue.filter { $0.isWaiting }.count
        let done = model.queue.filter { $0.status == .done }.count
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
    let presets: [Preset]
    let defaultName: String?
    let onRemove: () -> Void

    var body: some View {
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
        .padding(.vertical, 3)
        .animation(.smooth, value: item.status)
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
            ProgressView(value: item.progress).controlSize(.small)
        case .done:
            HStack(spacing: 10) {
                if let r = item.result, !r.peaks.isEmpty {
                    WaveformView(peaks: r.peaks, removed: r.removed)
                        .frame(height: 22)
                        .transition(.opacity)
                } else if let r = item.result, r.origSeconds > 0 {
                    ReductionBar(kept: max(0, min(1, r.newSeconds / r.origSeconds)))
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        case .waiting where !presets.isEmpty:
            Picker("Preset", selection: $item.presetID) {
                Text(defaultName.map { "Default (\($0))" } ?? "Default").tag(UUID?.none)
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
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from queue")
        case .running:
            Text("\(Int(item.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        case .done:
            Button {
                if let path = item.result?.output {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help("Show in Finder")
            .transition(.scale.combined(with: .opacity))
        case .failed, .cancelled:
            EmptyView()
        }
    }

    private var glyph: String {
        switch item.status {
        case .waiting:   return "circle.dotted"
        case .running:   return "circle.dotted"   // unused (spinner shown instead)
        case .done:      return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var glyphStyle: AnyShapeStyle {
        switch item.status {
        case .done:    return AnyShapeStyle(.green)
        case .failed:  return AnyShapeStyle(.red)
        default:       return AnyShapeStyle(.secondary)
        }
    }

    private var detail: String {
        switch item.status {
        case .waiting:   return "Waiting"
        case .running:   return "Cleaning\u{2026}"
        case .cancelled: return "Canceled"
        case .failed:    return item.error ?? "Couldn\u{2019}t be cleaned"
        case .done:
            if let r = item.result {
                return "removed \(formatTime(r.savedSeconds))"
            }
            return "Cleaned"
        }
    }
}

/// The signature view: the file's actual audio as peak bars, with the slices Crisp
/// cut drawn dim and the kept audio in green. Built from the engine's waveform
/// summary, so it shows exactly what was removed — honest, and unmistakably Crisp.
private struct WaveformView: View {
    let peaks: [Double]
    let removed: [Bool]

    var body: some View {
        Canvas { context, size in
            let n = peaks.count
            guard n > 0 else { return }
            let gap: CGFloat = n > 90 ? 0.5 : 1
            let barW = max(0.75, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let mid = size.height / 2
            for i in 0..<n {
                let x = CGFloat(i) * (barW + gap)
                let h = max(1.5, CGFloat(peaks[i]) * size.height)
                let rect = CGRect(x: x, y: mid - h / 2, width: barW, height: h)
                let isCut = i < removed.count && removed[i]
                let style: GraphicsContext.Shading = isCut
                    ? .color(.secondary.opacity(0.28))
                    : .color(.green)
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: style)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Audio waveform with removed sections dimmed")
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
