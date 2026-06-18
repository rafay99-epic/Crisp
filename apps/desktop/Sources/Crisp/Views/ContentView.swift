import SwiftUI
import UniformTypeIdentifiers
import CrispCore

struct ContentView: View {
    @Bindable var model: CleanModel
    @Bindable var updater: Updater
    @Bindable var modelStore: ModelStore
    @Bindable var settings: EngineSettings
    @Bindable var watchAgent: WatchAgentController
    @Bindable var onboarding: OnboardingController
    @State private var importing = false
    @State private var showUltraSheet = false
    @State private var ultraTarget = 1
    @State private var ultraVerdict: ResourceGovernor.Verdict?

    /// Filler-word removal needs the speech model; pauses-only doesn't.
    private var needsModel: Bool { model.removeFillers }

    /// "Clean Video" for one queued file, "Clean N Videos" for a batch.
    private var cleanButtonTitle: String {
        let pending = model.queue.filter { $0.isWaiting }.count
        return pending <= 1 ? "Clean Video" : "Clean \(pending) Videos"
    }

    /// Resolve a queued file's recipe: its own preset if set, else the window's
    /// default preset, else the live global strength + settings.
    private func resolveParameters(_ item: QueueItem) -> CleanParameters {
        if let preset = settings.preset(withID: item.presetID) { return preset.parameters() }
        if let preset = settings.defaultPreset { return preset.parameters() }
        return model.strength.parameters(using: settings.config)
    }

    /// Decide the parallel count from the governor, and for Ultra gate on a
    /// free-resource preflight before starting.
    private func attemptStart() {
        let snapshot = SystemProbe.snapshot()
        let mode = ConcurrencyMode(storage: settings.concurrencyMode)
        let plan = ResourceGovernor.plannedConcurrency(mode: mode, snapshot: snapshot, config: settings.config)
        if mode == .ultra {
            let verdict = ResourceGovernor.preflight(requested: plan, snapshot: snapshot, config: settings.config)
            guard verdict.fits else {
                ultraTarget = plan
                ultraVerdict = verdict
                showUltraSheet = true
                return
            }
        }
        launch(concurrency: plan)
    }

    /// Re-run the Ultra preflight (the sheet's "Check Again"): start if it now fits,
    /// otherwise refresh the shortfall shown in the sheet.
    private func recheckUltra() {
        let snapshot = SystemProbe.snapshot()
        let verdict = ResourceGovernor.preflight(requested: ultraTarget, snapshot: snapshot, config: settings.config)
        if verdict.fits {
            showUltraSheet = false
            launch(concurrency: ultraTarget)
        } else {
            ultraVerdict = verdict
        }
    }

    private func launch(concurrency: Int) {
        Task {
            await model.start(modelPath: modelStore.readyModelPath,
                              concurrency: concurrency,
                              resolveParameters: resolveParameters)
        }
    }
    private var modelBlocks: Bool { needsModel && !modelStore.state.isReady }

    var body: some View {
        // The welcome flow owns the whole window on first launch — the main app
        // stays hidden until onboarding is finished or skipped.
        if onboarding.isPresented {
            OnboardingView(onboarding: onboarding, modelStore: modelStore,
                           settings: settings, watchAgent: watchAgent)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            UpdateBanner(updater: updater)
            DropCard(model: model, importing: $importing)
            if !model.queue.isEmpty {
                QueueView(model: model, settings: settings)
            }
            OptionsCard(model: model)
            BackupStatusView(backupOn: settings.backupOriginal)
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
        .sheet(isPresented: $showUltraSheet) {
            if let verdict = ultraVerdict {
                UltraPreflightSheet(target: ultraTarget, verdict: verdict,
                                    onCheckAgain: recheckUltra,
                                    onCancel: { showUltraSheet = false })
            }
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
                Text("Remove pauses & filler words from your recordings.")
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
                attemptStart()
            } label: {
                HStack {
                    Image(systemName: "scissors")
                    Text(cleanButtonTitle)
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.hasPendingWork || modelBlocks)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
