import SwiftUI
import AppKit
import CrispCore

/// The clean queue — one row per video, with per-file status and progress. Waiting
/// rows can be reordered (top runs first), removed, and assigned a preset; running
/// and finished rows are fixed. Shown once at least one file has been added.
struct QueueView: View {
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings

    /// Cap the list height so a long queue scrolls instead of growing the window
    /// unbounded (the window sizes itself to its content).
    private var listHeight: CGFloat {
        let rows = CGFloat(model.queue.count)
        return min(max(rows, 1) * 48 + 8, 320)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Queue").font(.headline)
                Spacer()
                Text(countLabel).font(.callout).foregroundStyle(.secondary)
            }
            List {
                ForEach($model.queue) { $item in
                    QueueRow(item: $item, presets: settings.presets,
                             defaultName: settings.defaultPreset?.name,
                             onRemove: { model.remove(item.id) })
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: model.moveWaiting)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: listHeight)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var countLabel: String {
        let waiting = model.queue.filter { $0.isWaiting }.count
        let done = model.queue.filter { $0.status == .done }.count
        if model.isRunning { return "\(done) of \(model.queue.count) done" }
        if waiting == model.queue.count { return "\(waiting) video\(waiting == 1 ? "" : "s")" }
        return "\(done) done · \(waiting) waiting"
    }
}

/// One queued video. Leading status glyph, filename, and a secondary line that's a
/// preset picker while waiting (or status detail otherwise); trailing control fits
/// the state (remove while waiting, reveal once done).
private struct QueueRow: View {
    @Binding var item: QueueItem
    let presets: [Preset]
    let defaultName: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.body)
                .foregroundStyle(glyphStyle)
                .frame(width: 18)

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
        .padding(.vertical, 2)
    }

    @ViewBuilder private var secondaryLine: some View {
        if item.status == .running {
            ProgressView(value: item.progress).controlSize(.small)
        } else if item.status == .waiting && !presets.isEmpty {
            Picker("Preset", selection: $item.presetID) {
                Text(defaultName.map { "Default (\($0))" } ?? "Default").tag(UUID?.none)
                ForEach(presets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        } else {
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
        case .failed, .cancelled:
            EmptyView()
        }
    }

    private var glyph: String {
        switch item.status {
        case .waiting:   return "circle.dotted"
        case .running:   return "arrow.triangle.2.circlepath"
        case .done:      return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var glyphStyle: AnyShapeStyle {
        switch item.status {
        case .done:    return AnyShapeStyle(.green)
        case .failed:  return AnyShapeStyle(.red)
        case .running: return AnyShapeStyle(.tint)
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
                return "Cleaned \u{2014} removed \(formatTime(r.savedSeconds))"
            }
            return "Cleaned"
        }
    }
}
