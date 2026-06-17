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
