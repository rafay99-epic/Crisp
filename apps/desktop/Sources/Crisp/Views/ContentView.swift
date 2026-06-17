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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Remove pauses & filler words \u{2014} your original is always kept safe.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.bottom, 2)
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

    private var actionButton: some View {
        Button {
            let params = model.strength.parameters(using: settings.config)
            Task { await model.start(modelPath: modelStore.readyModelPath, parameters: params) }
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
