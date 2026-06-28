import SwiftUI
import UniformTypeIdentifiers
import CrispCore

struct ContentView: View {
    @Bindable var model: CleanModel
    @Bindable var updater: Updater
    @Bindable var modelStore: ModelStore
    @Bindable var fillerModelStore: ModelStore
    @Bindable var fillerUpdater: FillerModelUpdater
    @Bindable var settings: EngineSettings
    @Bindable var watchAgent: WatchAgentController
    @Bindable var onboarding: OnboardingController
    @Bindable var player: PreviewPlayer
    @Bindable var whatsNew: WhatsNewController
    @Environment(\.openWindow) private var openWindow
    @State private var importing = false
    @State private var showUltraSheet = false
    @State private var ultraTarget = 1
    @State private var ultraVerdict: ResourceGovernor.Verdict?
    @State private var estimate = EstimateModel()

    /// Any waiting file asking for captions (checks the *resolved* recipe, so a
    /// per-row preset that turns captions on is covered). Captions always use whisper.
    private var anyCaptions: Bool {
        model.queue.contains { item in
            item.status == .waiting && resolveParameters(item).captionsFormat != "none"
        }
    }
    /// The fast on-device classifier is the active filler backend: it's only used when
    /// filler removal is on AND the user opted into it. (With fillers off it isn't the
    /// backend even when enabled, so whisper handles retakes.) When active it does the
    /// fillers without whisper, and retake removal is skipped (it needs a transcript).
    private var classifierActive: Bool {
        model.removeFillers && settings.fillerModelEnabled
    }
    /// Whisper is needed for captions and for filler/retake removal — but not when the
    /// classifier is the active backend (it does the fillers, and retakes are skipped
    /// then). Mirrors the engine's `use_classifier`, so the run never starts expecting
    /// the classifier and then hits a missing-whisper-model failure.
    private var needsWhisper: Bool {
        anyCaptions || ((model.removeFillers || model.removeRetakes) && !classifierActive)
    }
    /// The on-device filler model is needed when filler removal is on and the user
    /// opted into the classifier backend.
    private var needsFillerModel: Bool {
        model.removeFillers && settings.fillerModelEnabled
    }
    /// The filler model is ready to run if it's downloaded — or, on a dev build, if a
    /// local model is sideloaded (which needs no download). Keeps the dev sideload from
    /// being blocked by the download gate.
    private var fillerModelReady: Bool {
        DevFillerModel.overridePath != nil || fillerModelStore.state.isReady
    }
    /// The active filler model path: a dev sideload overrides the downloaded model.
    private var activeFillerModelPath: String? {
        DevFillerModel.overridePath ?? fillerModelStore.readyModelPath
    }

    /// Everything a pre-flight estimate depends on — the global recipe (strength +
    /// custom cut knobs) and the waiting files with their per-row presets. Order is
    /// sorted so reordering the queue (which doesn't change the total) doesn't
    /// needlessly clear a valid estimate.
    private var estimateSignature: String {
        let waiting = model.queue.filter { $0.status == .waiting }
            .map { "\($0.id)|\($0.presetID?.uuidString ?? "")" }
            .sorted()
            .joined(separator: ",")
        return "\(model.strength.rawValue)|\(settings.pauseThreshold)|\(settings.breathingRoom)"
            + "|\(settings.minKeep)|\(settings.silenceFloorDB)|\(waiting)"
    }

    /// Pre-flight estimate of how much the waiting files would shrink (pauses only).
    private func runEstimate() {
        let items = model.queue.filter { $0.status == .waiting }
            .map { (url: $0.url, params: resolveParameters($0)) }
        estimate.estimate(items)
    }

    /// Resolve a queued file's recipe: its own preset if it has one, otherwise the
    /// live global strength + settings shown in the bottom bar. (A "default for new
    /// files" preset is stamped onto rows when they're added, so a row with no
    /// preset genuinely means "use the global controls" — no hidden override.)
    private func resolveParameters(_ item: QueueItem) -> CleanParameters {
        // Editor handoff is a global output mode, so it applies even to preset-backed
        // rows (the preset's recipe otherwise wouldn't carry it).
        if let preset = settings.preset(withID: item.presetID) {
            return preset.parameters(exportToEditor: settings.exportToEditor)
        }
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
                              fillerModelPath: needsFillerModel ? activeFillerModelPath : nil,
                              feedbackModelID: (needsFillerModel && settings.shareFillerData)
                                  ? settings.selectedFillerModelID : nil,
                              concurrency: concurrency,
                              resolveParameters: resolveParameters)
        }
    }
    private var modelBlocks: Bool {
        (needsWhisper && !modelStore.state.isReady)
            || (needsFillerModel && !fillerModelReady)
    }

    var body: some View {
        // The welcome flow owns the whole window on first launch — the main app
        // stays hidden until onboarding is finished or skipped.
        if onboarding.isPresented {
            OnboardingView(onboarding: onboarding, modelStore: modelStore,
                           settings: settings, watchAgent: watchAgent)
        } else {
            workspace
        }
    }

    /// The working layout: transient banners on top, then either the empty-state
    /// hero (no files yet) or the queue list filling the window above a pinned
    /// bottom bar. The window is resizable, so the list — not the chrome — takes
    /// the slack on any screen size.
    private var workspace: some View {
        VStack(spacing: 0) {
            UpdateBanner(updater: updater)
            // A newer filler model is on Hugging Face — offer the update here too,
            // not only in Settings (mirrors the app's update banner).
            if settings.fillerModelEnabled {
                FillerUpdateBar(updater: fillerUpdater, store: fillerModelStore)
                    .padding(.horizontal, 16).padding(.top, 10)
            }
            if needsFillerModel && DevFillerModel.overridePath == nil
                && (!fillerModelStore.state.isReady || fillerModelStore.state.isBusy) {
                ModelStatusView(store: fillerModelStore)
                    .padding(.horizontal, 16).padding(.top, 10)
            } else if needsWhisper && (!modelStore.state.isReady || modelStore.state.isBusy) {
                ModelStatusView(store: modelStore)
                    .padding(.horizontal, 16).padding(.top, 10)
            }
            if model.queue.isEmpty {
                emptyHero
            } else {
                QueueView(model: model, settings: settings, player: player)
                Divider()
                BottomBar(model: model, settings: settings, estimate: estimate,
                          modelBlocks: modelBlocks, onStart: attemptStart, onEstimate: runEstimate)
            }
        }
        // Min width keeps the bottom bar's recipe + action on one line (no wrapping)
        // at the smallest size; the queue takes any extra height/width.
        .frame(minWidth: 600, minHeight: 460)
        .background(.background)
        // After an update, introduce the release's new features once. Runs only when
        // the workspace is showing (i.e. not during onboarding, which covers them).
        .task {
            whatsNew.presentIfNeeded(onboardingActive: onboarding.isPresented,
                                     onboardingAppearedOnLaunch: onboarding.appearedOnLaunch)
        }
        .sheet(isPresented: $whatsNew.isPresented) {
            WhatsNewView(whatsNew: whatsNew, onDismiss: { whatsNew.isPresented = false })
        }
        // Keep the "default for new files" preset the model stamps onto added rows
        // in sync with Settings, in both directions and at first appearance.
        .onChange(of: settings.defaultPresetID, initial: true) {
            model.newItemPresetID = settings.defaultPreset?.id
        }
        // A prior estimate goes stale when anything it depends on changes — the
        // global strength + custom knobs, or which files are waiting and their
        // per-row presets. (Sorted, so a harmless reorder doesn't clear it.)
        .onChange(of: estimateSignature) { estimate.reset() }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("Add Videos", systemImage: "plus") }
                    .help("Add videos")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "history") } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .help("History")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
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

    /// Empty state — app identity + the inviting drop zone, centered. This is the
    /// focused single-purpose look the app opens with.
    private var emptyHero: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            header
            DropCard(model: model, importing: $importing)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
}
