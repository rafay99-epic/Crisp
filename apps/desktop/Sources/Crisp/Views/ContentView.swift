import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: CleanModel
    @Bindable var updater: Updater
    @Bindable var modelStore: ModelStore
    @Bindable var settings: EngineSettings
    @State private var importing = false

    /// Filler-word removal needs the speech model; pauses-only doesn't.
    private var needsModel: Bool { model.removeFillers }
    private var modelBlocks: Bool { needsModel && !modelStore.state.isReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
        .background(.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.movie, .video, .audiovisualContent],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addFiles(urls) }
        }
    }

    /// App identity — the real app icon (per-channel) + wordmark + tagline.
    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
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
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var actionButton: some View {
        if model.isRunning {
            Button(role: .cancel) {
                model.cancel()
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancel")
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
            .keyboardShortcut(.cancelAction)
        } else {
            Button {
                let params = model.strength.parameters(using: settings.config)
                Task { await model.start(modelPath: modelStore.readyModelPath, parameters: params) }
            } label: {
                HStack {
                    Image(systemName: "scissors")
                    Text("Clean Video")
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.files.isEmpty || modelBlocks)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
