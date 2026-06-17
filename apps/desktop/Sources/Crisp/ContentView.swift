import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: CleanModel
    @Bindable var updater: Updater
    @Bindable var modelStore: ModelStore
    @State private var importing = false

    /// Filler-word removal needs the speech model; pauses-only doesn't.
    private var needsModel: Bool { model.removeFillers }
    private var modelBlocks: Bool { needsModel && !modelStore.state.isReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            UpdateBanner(updater: updater)
            DropCard(model: model, importing: $importing)
            OptionsCard(model: model)
            if modelBlocks || modelStore.state.isBusy {
                ModelStatusView(store: modelStore)
            }
            actionButton
            if model.isRunning || !model.results.isEmpty || model.errorMessage != nil {
                ProgressSection(model: model)
            }
            if !model.results.isEmpty && !model.isRunning {
                ResultCard(model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.movie, .video, .audiovisualContent],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addFiles(urls) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Crisp").font(.title.bold())
                    if let badge = Channel.current.badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.tint.opacity(0.2)))
                            .foregroundStyle(.tint)
                    }
                }
                Text("Remove pauses & filler words. Your original is always kept safe.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var actionButton: some View {
        Button {
            Task { await model.start(modelPath: modelStore.readyModelPath) }
        } label: {
            HStack {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Cleaning\u{2026}")
                } else {
                    Image(systemName: "scissors")
                    Text("Clean Video")
                }
            }
            .frame(maxWidth: .infinity)
            .font(.headline)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.files.isEmpty || model.isRunning || modelBlocks)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

/// First-run / resume / repair surface for the whisper speech model. One shared
/// card across every state — missing, downloading, verifying, failed — so the
/// download experience lives in exactly one place.
struct ModelStatusView: View {
    @Bindable var store: ModelStore

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .downloading(let p) = store.state, p >= 0 {
                    ProgressView(value: p).padding(.top, 4)
                }
            }
            Spacer()
            trailing
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.25)))
    }

    @ViewBuilder private var icon: some View {
        switch store.state {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(.orange)
        case .downloading, .verifying, .checking:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.title2).foregroundStyle(.tint)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch store.state {
        case .absent:
            Button("Download") { store.download() }.controlSize(.large)
        case .downloading:
            Button("Cancel") { store.cancel() }.controlSize(.small)
        case .failed:
            Button("Try Again") { store.download() }.controlSize(.large)
        default:
            EmptyView()
        }
    }

    private var title: String {
        switch store.state {
        case .checking:    return "Checking speech model\u{2026}"
        case .ready:       return "Speech model ready"
        case .absent:      return "Speech model needed"
        case .downloading: return "Downloading speech model\u{2026}"
        case .verifying:   return "Verifying speech model\u{2026}"
        case .failed:      return "Couldn\u{2019}t download speech model"
        }
    }

    private var subtitle: String {
        switch store.state {
        case .downloading(let p) where p >= 0:
            return "\(Int(p * 100))% \u{2014} keep Crisp open until it finishes."
        case .downloading:
            return "Keep Crisp open until it finishes."
        case .failed(let msg):
            return msg
        default:
            return "A one-time ~148 MB download lets Crisp find filler words. "
                 + "Turn off \u{201C}Remove filler words\u{201D} to skip it."
        }
    }
}

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
            .background(RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.12)))
        } else if updater.status == .downloading || updater.status == .installing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(updater.status == .downloading ? "Downloading update\u{2026}" : "Installing update\u{2026}")
                    .font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.3)))
        }
    }
}

struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.files.isEmpty ? "film.stack" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.files.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text("Drag a video here, or").font(.callout).foregroundStyle(.secondary)
            Button("Choose video\u{2026}") { importing = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(targeted ? 0.6 : 0.25)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls)
            return true
        } isTargeted: { targeted = $0 }
        .disabled(model.isRunning)
    }

    private var title: String {
        if model.files.isEmpty { return "No video selected" }
        if model.files.count == 1 { return model.files[0].lastPathComponent }
        return "\(model.files.count) videos selected"
    }
}

struct OptionsCard: View {
    @Bindable var model: CleanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How much to cut").font(.headline)
                Picker("", selection: $model.strength) {
                    ForEach(Strength.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(model.strength.detail)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Toggle(isOn: $model.removeFillers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove filler words").font(.headline)
                    Text("um, uh, hmm, erm, aww\u{2026}").font(.callout).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.25)))
        .disabled(model.isRunning)
    }
}

struct ProgressSection: View {
    @Bindable var model: CleanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: model.progress)
                .tint(model.errorMessage == nil ? .accentColor : .red)
            HStack {
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.logLines.isEmpty {
                DisclosureGroup("Details") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(model.logLines.enumerated()), id: \.offset) { i, line in
                                    Text(line).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.2)))
                        .onChange(of: model.logLines.count) { _, c in
                            withAnimation { proxy.scrollTo(c - 1, anchor: .bottom) }
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}

struct ResultCard: View {
    @Bindable var model: CleanModel

    private var totalSaved: Double { model.results.reduce(0) { $0 + $1.savedSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.results.count == 1 ? "Cleaned!" : "Cleaned \(model.results.count) videos")
                        .font(.headline)
                    Text("Removed \(formatTime(totalSaved)) of pauses & fillers.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let first = model.results.first, model.results.count == 1 {
                HStack(spacing: 16) {
                    stat("\(formatTime(first.origSeconds)) \u{2192} \(formatTime(first.newSeconds))", "Length")
                    stat("\(first.pauses)", "Pauses cut")
                    stat("\(first.fillers)", "Fillers cut")
                }
            }
            HStack {
                Button {
                    if let path = model.results.last?.output {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } label: { Label("Show in Finder", systemImage: "folder") }
                .controlSize(.large)

                Button { model.reset() } label: {
                    Label("Clean another", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.green.opacity(0.12)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
