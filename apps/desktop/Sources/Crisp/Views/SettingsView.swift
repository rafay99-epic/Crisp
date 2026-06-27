import SwiftUI
import AppKit
import ServiceManagement
import CrispCore

/// The ⌘, Settings window. Organized into native preference tabs (Cutting, Output,
/// Presets, Automation, General) rather than one long scroll, so each group of
/// options is scannable on its own. Values persist to `~/.crisp*/config/settings.json`.
struct SettingsView: View {
    @Bindable var settings: EngineSettings
    @Bindable var updater: Updater
    @Bindable var watchAgent: WatchAgentController
    @Bindable var modelStore: ModelStore
    @Bindable var fillerModelStore: ModelStore
    @Bindable var fillerUpdater: FillerModelUpdater
    @Bindable var fillerVersions: FillerModelVersions
    @Bindable var model: CleanModel

    @State private var newPresetName = ""
    @State private var snapshot = SystemProbe.snapshot()
    /// Dev sideload: the local model path picked in this build (mirrors
    /// `DevFillerModel.pickedPath`; `@State` so the UI refreshes after picking).
    @State private var devLocalModel: String? = DevFillerModel.pickedPath

    /// Whether the chosen container dictates its own codecs (WebM → VP9 + Opus),
    /// in which case the codec controls are disabled. Reads the rule off the enum
    /// so it stays in one place as containers are added.
    private var isWebM: Bool {
        OutputContainer(rawValue: settings.outputContainer)?.forcesOwnCodecs ?? false
    }

    /// The running build, e.g. "0.12" or "0.12 (build 34)" on Nightly.
    private var versionString: String {
        Updater.currentBuildNumber > 0
            ? "\(Updater.currentVersion) (build \(Updater.currentBuildNumber))"
            : Updater.currentVersion
    }

    // MARK: - Window

    var body: some View {
        TabView {
            tab { cuttingSection; retakeSection; smoothingSection; speechModelSection; fillerModelSection }
                .tabItem { Label("Cutting", systemImage: "scissors") }

            tab { encodingSection; captionsSection; outputLocationSection; originalsSection }
                .tabItem { Label("Output", systemImage: "film.stack") }

            tab { presetsSection }
                .tabItem { Label("Presets", systemImage: "square.stack.3d.up") }

            tab { watchSection; menuBarSection }
                .tabItem { Label("Automation", systemImage: "wand.and.rays") }

            tab { performanceSection; softwareUpdateSection; diagnosticsSection; restoreDefaultsSection }
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 560)
        .onAppear { watchAgent.refresh(); snapshot = SystemProbe.snapshot() }
    }

    /// One settings tab: a grouped Form of the given sections. Centralizes the style
    /// so every tab matches.
    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
    }

    // MARK: - Cutting

    /// Describes one slider row (keeps the row builder to a single argument).
    private struct Knob {
        let title: String
        let help: String
        let unit: String
        let range: ClosedRange<Double>
        let step: Double
        var decimals: Int = 2
    }

    @ViewBuilder private var cuttingSection: some View {
        Section {
            row(Knob(title: "Pause threshold", help: "Cut silences longer than this.",
                     unit: "s", range: 0.1...2.0, step: 0.05), $settings.pauseThreshold)
            row(Knob(title: "Silence floor", help: "Audio quieter than this counts as silence.",
                     unit: "dB", range: -45...(-15), step: 1, decimals: 0), $settings.silenceFloorDB)
            row(Knob(title: "Breathing room", help: "Padding kept on each side of a cut.",
                     unit: "s", range: 0...0.5, step: 0.01), $settings.breathingRoom)
            row(Knob(title: "Minimum keep", help: "Drop kept fragments shorter than this.",
                     unit: "s", range: 0...0.5, step: 0.01), $settings.minKeep)
        } header: {
            Text("Custom cutting")
        } footer: {
            Text("Applied when \u{201C}How much to cut\u{201D} is set to Custom.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var retakeSection: some View {
        Section {
            Picker("Sensitivity", selection: $settings.retakeSensitivity) {
                ForEach(RetakeSensitivity.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            // Retake detection reads the transcript, which the fast on-device filler
            // model can't produce — so it's unavailable while that model is on, the
            // same way captions are. Disable the control and say so clearly.
            .disabled(settings.fillerModelEnabled)
            if settings.fillerModelEnabled {
                Label {
                    Text("**Not available with our custom fast model.** Finding repeated takes needs the speech model to read your words \u{2014} the fast filler model can't transcribe. Turn it off (below) to use the more powerful speech model.")
                        .font(.caption).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } else {
                Text(RetakeSensitivity(rawValue: settings.retakeSensitivity)?.detail ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Repeated takes")
        } footer: {
            Text("When you flub a line and immediately say it again, Crisp keeps the corrected take and cuts the first. Turn it on/off per clean with \u{201C}Remove repeated takes.\u{201D} Needs the speech model.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var smoothingSection: some View {
        Section {
            row(Knob(title: "Audio fade", help: "A tiny fade in/out at each cut so joins don\u{2019}t click. 0 turns it off.",
                     unit: "ms", range: 0...50, step: 1, decimals: 0), $settings.fadeMs)
            row(Knob(title: "Crossfade", help: "Dissolve between segments instead of a hard cut. 0 keeps hard cuts.",
                     unit: "ms", range: 0...500, step: 10, decimals: 0), $settings.crossfadeMs)
            row(Knob(title: "Snap to zero-crossing", help: "Nudge each cut onto a nearby point where the audio waveform crosses zero, for a cleaner splice. 0 turns it off.",
                     unit: "ms", range: 0...30, step: 1, decimals: 0), $settings.snapMs)
        } header: {
            Text("Cut smoothing")
        } footer: {
            Text("Applied to every clean \u{2014} reduces the clicks and abrupt jumps at each cut.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Output / Encoding

    @ViewBuilder private var encodingSection: some View {
        Section {
            Picker("Output format", selection: $settings.outputContainer) {
                ForEach(OutputContainer.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Text(isWebM
                 ? "WebM always uses VP9 video and Opus audio. It\u{2019}s the most web-friendly format, but slower to encode (no hardware VP9 encoder)."
                 : "\u{201C}Same as input\u{201D} keeps each video\u{2019}s original container \u{2014} an .mkv stays .mkv, an .mp4 stays .mp4.")
                .font(.caption).foregroundStyle(.secondary)

            // WebM dictates its own codecs, so these don't apply when it's chosen.
            Group {
                Picker("Video format", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Hardware acceleration", isOn: $settings.hardwareEncoding)
                Text("Apple VideoToolbox \u{2014} faster, but software gives slightly better quality per file size.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Audio format", selection: $settings.audioCodec) {
                    ForEach(AudioCodec.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            .disabled(isWebM)

            // Quality (VP9's CRF too) and bitrate (Opus too) always apply.
            Picker("Quality", selection: $settings.videoQuality) {
                ForEach(VideoQuality.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Audio bitrate", selection: $settings.audioBitrateKbps) {
                ForEach([128, 160, 192, 256], id: \.self) { Text("\($0) kbps").tag($0) }
            }

            // Frame rate — screen recordings (OBS, macOS capture) are often variable
            // frame rate, which the cut render can drift A/V on. "Automatic" fixes that.
            Picker("Frame rate", selection: $settings.frameRateMode) {
                ForEach(FrameRateMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if let mode = FrameRateMode(rawValue: settings.frameRateMode) {
                Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                if mode.usesValue {
                    // settings.json may hold any engine-accepted rate (a power user can
                    // hand-edit it); fold a non-preset value into the list so the picker
                    // can represent the current selection instead of showing blank.
                    let rates = commonFrameRates.contains(settings.frameRateValue)
                        ? commonFrameRates
                        : ([settings.frameRateValue] + commonFrameRates).sorted()
                    Picker("Constant rate", selection: $settings.frameRateValue) {
                        ForEach(rates, id: \.self) { Text(Self.frameRateLabel($0)).tag($0) }
                    }
                }
            }
        } header: {
            Text("Encoding")
        } footer: {
            Text("Applied to every clean. Cuts are always re-encoded, so these set the output quality.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "30 fps" for whole rates, "29.97 fps" for the broadcast fractional ones.
    static func frameRateLabel(_ fps: Double) -> String {
        let whole = fps.rounded() == fps
        return whole ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
    }

    @ViewBuilder private var captionsSection: some View {
        Section {
            Picker("Subtitle files", selection: $settings.captionsFormat) {
                ForEach(CaptionFormat.allCases) { Text($0.label).tag($0.rawValue) }
            }
            // Captions are transcribed, which only the speech model can do — the custom
            // fast filler model (Wren) detects filler audio but can't produce text. So
            // captions are unavailable while the fast model is on (it's cleared on enable).
            .disabled(settings.fillerModelEnabled)
            if settings.fillerModelEnabled {
                Label {
                    Text("**This feature might not be available with our custom fast model.** Captions need the speech model to transcribe \u{2014} turn off the fast filler model (Cutting tab) to add them.")
                        .font(.caption).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Captions")
        } footer: {
            Text(settings.captionsFormat == "none"
                 ? "Turn this on to also write a subtitle file (.srt or .vtt) next to each cleaned video \u{2014} ready for YouTube, Premiere, or the web. Captions are transcribed, so they need the speech model."
                 : "Crisp writes the subtitles re-timed to the cut video, so they stay in sync after pauses and fillers are removed. Filler words are left out of the captions.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var outputLocationSection: some View {
        Section {
            LabeledContent("Cleaned files") {
                HStack(spacing: 8) {
                    Text(outputLocationName)
                        .foregroundStyle(settings.outputDirectory.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose\u{2026}") { chooseOutputFolder() }
                        .controlSize(.small)
                }
            }
            if !settings.outputDirectory.isEmpty {
                Button("Use the source video\u{2019}s folder") { settings.outputDirectory = "" }
                    .controlSize(.small)
            }
            Toggle("Also export separate video & audio", isOn: $settings.splitTracks)
            if settings.splitTracks {
                Picker("Audio track format", selection: $settings.splitAudioFormat) {
                    ForEach(SplitAudioFormat.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
        } header: {
            Text("Output location")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.outputDirectory.isEmpty
                     ? "Cleaned videos are saved next to the original \u{2014} the same folder you picked the video from."
                     : "Cleaned videos are saved into this folder (e.g. a NAS). The original stays where it is.")
                Text(settings.splitTracks
                     ? "Alongside each cleaned file, Crisp also writes a video-only and an audio-only copy \u{2014} so you can animate the picture while keeping the cleaned voiceover."
                     : "Turn on \u{201C}separate video & audio\u{201D} to also get the picture and sound as their own files for editing.")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var originalsSection: some View {
        Section {
            Toggle("Keep a backup of the original", isOn: $settings.backupOriginal)
        } header: {
            Text("Originals")
        } footer: {
            Text(settings.backupOriginal
                 ? "Before each clean, your original is copied into a dated folder under \u{201C}Originals\u{201D} in Crisp\u{2019}s home folder. Crisp never edits or deletes your source file."
                 : "Crisp won\u{2019}t copy your original. It still never edits or deletes your source file \u{2014} only a new cleaned copy is written.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Speech model

    /// Switching the active model persists the choice and retargets the store, which
    /// rechecks disk (so picking an already-installed model is instantly ready).
    private var activeModelBinding: Binding<String> {
        Binding(get: { settings.selectedModelID },
                set: { id in
                    settings.selectedModelID = id
                    AppInfo.logger("model").info("speech model selected: \(id, privacy: .public)")
                    modelStore.use(ModelCatalog.spec(id: id))
                })
    }

    @ViewBuilder private var speechModelSection: some View {
        Section {
            if settings.fillerModelEnabled {
                // Mutually exclusive with the on-device filler model: when Wren is on,
                // whisper isn't used for fillers, so its picker is hidden here.
                Label(settings.captionsFormat == "none"
                      ? "The on-device filler model (below) is handling filler detection — the speech model isn't used."
                      : "The on-device filler model (below) handles fillers; the speech model is still used for captions.",
                      systemImage: "bird")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: activeModelBinding) {
                    ForEach(ModelCatalog.all) { Text($0.displayName).tag($0.id) }
                }
                // Don't switch mid-download, or mid-clean (the running clean already
                // locked in its model — switching would only mislead).
                .disabled(modelStore.state.isBusy || model.isRunning)
                Text(modelStore.spec.summary)
                    .font(.caption).foregroundStyle(.secondary)
                ModelInstallControl(store: modelStore, allowRemove: true, removeDisabled: model.isRunning)
            }
        } header: {
            Text("Speech model")
        } footer: {
            Text("Used to find filler words (and to write captions). Larger models catch more fillers and place cuts more precisely, but download and run slower. Pauses are detected from the audio either way.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Enabling the on-device filler model rechecks disk (so an already-installed
    /// model shows ready immediately); switching models retargets its store.
    private var fillerEnabledBinding: Binding<Bool> {
        Binding(get: { settings.fillerModelEnabled },
                set: { on in
                    settings.fillerModelEnabled = on
                    AppInfo.logger("model").info("filler model \(on ? "enabled" : "disabled")")
                    if on {
                        // Hard-disable captions: they need whisper (the fast model can't
                        // transcribe), so clear any caption setting rather than silently
                        // falling back to the speech model and bypassing the fast model.
                        if settings.captionsFormat != "none" {
                            settings.captionsFormat = "none"
                            AppInfo.logger("model").info("captions cleared — unavailable with the fast filler model")
                        }
                        Task { await fillerModelStore.refresh() }
                    }
                })
    }
    private var activeFillerModelBinding: Binding<String> {
        Binding(get: { settings.selectedFillerModelID },
                set: { id in
                    settings.selectedFillerModelID = id
                    AppInfo.logger("model").info("filler model selected: \(id, privacy: .public)")
                    fillerModelStore.use(FillerModelCatalog.spec(id: id))
                })
    }

    @ViewBuilder private var fillerModelSection: some View {
        Section {
            Toggle("Use the fast on-device filler model", isOn: fillerEnabledBinding)
                .disabled(model.isRunning)
            if settings.fillerModelEnabled {
                Label {
                    Text("**English only.** Experimental — built for clear English speech. It can occasionally cut a real word, and it won't work on other languages. For non-English audio, captions, or removing repeated takes, turn this off and use the speech model.")
                        .font(.caption).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Picker("Model", selection: activeFillerModelBinding) {
                    ForEach(FillerModelCatalog.all) { Text($0.displayName).tag($0.id) }
                }
                .disabled(fillerModelStore.state.isBusy || model.isRunning)
                Text(fillerModelStore.spec.summary)
                    .font(.caption).foregroundStyle(.secondary)
                ModelInstallControl(store: fillerModelStore, allowRemove: true, removeDisabled: model.isRunning)
                if case .available(let version) = fillerUpdater.state {
                    HStack {
                        Label("Model update available — v\(version)", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                        Spacer()
                        Button("Update") { Task { await fillerUpdater.apply(using: fillerModelStore) } }
                            .disabled(fillerModelStore.state.isBusy || model.isRunning)
                    }
                }
                Toggle("Share anonymous data to help improve the model", isOn: $settings.shareFillerData)
                Text("On-device only. Records counts + durations (never your audio, filenames, or any content) to ~/.crisp/feedback. Nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                if Channel.current.showsModelDevTools { devModelTools }
            }
        } header: {
            Text("Filler detection (experimental)")
        } footer: {
            Text("A tiny on-device model that spots um/uh much faster than transcribing — used instead of the speech model above when removing fillers. English only; off by default. Captions and repeated-take removal still need the speech model.")
                .font(.caption).foregroundStyle(.secondary)
        }
        // Dev build: load the published version history so the picker can offer old models.
        .task(id: settings.fillerModelEnabled) {
            guard Channel.current.showsModelDevTools, settings.fillerModelEnabled else { return }
            await fillerVersions.load(repoModelURL: fillerModelStore.spec.url)
        }
    }

    // MARK: - Filler model — developer tools (dev build only)

    /// Two dev-only affordances mirroring the app's dev flow for ML:
    /// • **Local sideload** — run a freshly trained `.mlmodel` from disk before
    ///   publishing anything (the `./dev.sh` of models).
    /// • **Version history** — install any published `v0.0.N` to A/B old vs new
    ///   (the git-history of models; the tags already exist on Hugging Face).
    @ViewBuilder private var devModelTools: some View {
        Divider()
        Label("Developer (Dev build only)", systemImage: "hammer")
            .font(.caption.bold()).foregroundStyle(.secondary)

        // Local sideload.
        if DevFillerModel.isEnvOverride {
            Label("Running the local model from $\(DevFillerModel.envKey).",
                  systemImage: "wrench.and.screwdriver")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local model").font(.callout)
                    Text(devLocalModel.map { ($0 as NSString).lastPathComponent }
                         ?? "Using the downloaded model")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if devLocalModel != nil {
                    Button("Clear") { devLocalModel = nil; DevFillerModel.pickedPath = nil }
                }
                Button("Load local model…") { pickLocalModel() }
                    .disabled(model.isRunning)
            }
            Text("Run a `.mlmodel` you just trained, before publishing. Put its `\(fillerModelStore.spec.displayName).config.json` beside it so framing + threshold travel too.")
                .font(.caption).foregroundStyle(.secondary)
        }

        // Version history (published v0.0.N tags).
        if !fillerVersions.versions.isEmpty {
            HStack {
                Text("Install version").font(.callout)
                Spacer()
                if let installing = fillerVersions.installing {
                    ProgressView().controlSize(.small)
                    Text("v\(installing)…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu("Choose…") {
                        ForEach(fillerVersions.versions, id: \.self) { v in
                            Button("v\(v)") {
                                AppInfo.logger("model").info("installing filler model version v\(v, privacy: .public)")
                                Task {
                                    await fillerVersions.install(version: v, baseSpec: fillerModelStore.spec,
                                                                 store: fillerModelStore)
                                }
                            }
                        }
                    }
                    .frame(width: 130)
                    .disabled(fillerModelStore.state.isBusy || model.isRunning)
                }
            }
            Text("Download any past model to compare it against the current one (\(fillerVersions.versions.count) published).")
                .font(.caption).foregroundStyle(.secondary)
        } else if fillerVersions.isLoading {
            Label("Loading version history…", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Pick a local `.mlmodel` to sideload (dev only). The native file picker is a
    /// genuine View concern; the async install/version workflow lives in
    /// `FillerModelVersions` (a Service), so the View only triggers + observes it.
    private func pickLocalModel() {
        let panel = NSOpenPanel()
        // Restrict to .mlmodel so a stray file can't be persisted as a model path.
        panel.allowedContentTypes = [.init(filenameExtension: "mlmodel")].compactMap { $0 }
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Model"
        if panel.runModal() == .OK, let url = panel.url {
            devLocalModel = url.path
            DevFillerModel.pickedPath = url.path
            AppInfo.logger("model").info("sideloaded local filler model: \(url.path, privacy: .public)")
        }
    }

    // MARK: - Performance

    private var concurrencyMode: ConcurrencyMode { ConcurrencyMode(storage: settings.concurrencyMode) }
    private var modeBinding: Binding<ConcurrencyMode> {
        Binding(get: { concurrencyMode }, set: { settings.concurrencyMode = $0.rawValue })
    }
    private var ceiling: Int { ResourceGovernor.hardwareCeiling(snapshot: snapshot, config: settings.config) }
    private var recommended: Int { ResourceGovernor.recommended(snapshot: snapshot, config: settings.config) }

    /// Selectable per-clean RAM budgets, labelled in GB.
    private let memoryBudgets = [1024, 1536, 2048, 3072, 4096]

    @ViewBuilder private var performanceSection: some View {
        Section {
            Picker("Cleaning at once", selection: modeBinding) {
                ForEach(ConcurrencyMode.allCases) { Text($0.label).tag($0) }
            }
            Text(concurrencyMode.detail)
                .font(.caption).foregroundStyle(.secondary)

            if concurrencyMode == .manual {
                Stepper("Run \(settings.manualConcurrency) at once",
                        value: $settings.manualConcurrency, in: 1...max(1, ceiling))
            }

            Picker("Memory per video", selection: $settings.perJobMemoryBudgetMB) {
                ForEach(memoryBudgets, id: \.self) { Text(gbLabel($0)).tag($0) }
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("This Mac can clean about \(recommended) at once right now (up to \(ceiling) when memory is free). Parallel cleaning is limited by the shared media engine and heat \u{2014} more at once isn\u{2019}t always faster.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func gbLabel(_ mb: Int) -> String {
        let gb = Double(mb) / 1024
        return gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)
    }

    // MARK: - Presets

    private var defaultPresetBinding: Binding<UUID?> {
        Binding(get: { UUID(uuidString: settings.defaultPresetID) },
                set: { settings.setDefaultPreset($0) })
    }

    private var trimmedNewPresetName: String {
        newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var presetsSection: some View {
        Section {
            ForEach($settings.presets) { $preset in
                HStack {
                    TextField("Name", text: $preset.name)
                        .textFieldStyle(.plain)
                    Spacer()
                    Button(role: .destructive) {
                        settings.deletePreset(preset.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete preset")
                }
            }
            HStack {
                TextField("New preset name\u{2026}", text: $newPresetName)
                Button("Add") {
                    settings.addPreset(named: trimmedNewPresetName, strength: .custom)
                    newPresetName = ""
                }
                .disabled(trimmedNewPresetName.isEmpty)
            }
            if !settings.presets.isEmpty {
                Picker("New files use", selection: defaultPresetBinding) {
                    Text("Current settings").tag(UUID?.none)
                    ForEach(settings.presets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("A preset saves the current cutting, encoding, output, and backup settings under a name. In the queue, pick a preset per file \u{2014} so different videos can be cleaned differently in one batch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Output location helpers

    private var outputLocationName: String {
        settings.outputDirectory.isEmpty
            ? "Same as the source video"
            : (settings.outputDirectory as NSString).abbreviatingWithTildeInPath
    }

    private func chooseOutputFolder() {
        if let path = FolderPicker.choosePath(message: "Choose where cleaned videos are saved.") {
            settings.outputDirectory = path
        }
    }

    // MARK: - Automation: Menu bar

    @ViewBuilder private var menuBarSection: some View {
        Section {
            Toggle("Show Crisp in the menu bar", isOn: $settings.menuBarEnabled)
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Adds a menu-bar item with a drop zone \u{2014} drop a video to clean it with your default recipe without opening this window.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Automation: Watch folder

    /// Toggling this both saves the preference and registers/unregisters the
    /// background LaunchAgent, so "on" really means "running in the background".
    private var watchEnabledBinding: Binding<Bool> {
        Binding(get: { settings.watchEnabled },
                set: { on in
                    settings.watchEnabled = on
                    watchAgent.setEnabled(on)
                })
    }

    private var watchFolderName: String {
        settings.watchFolderPath.isEmpty
            ? "No folder chosen"
            : (settings.watchFolderPath as NSString).abbreviatingWithTildeInPath
    }

    @ViewBuilder private var watchSection: some View {
        Section {
            LabeledContent("Folder") {
                HStack(spacing: 8) {
                    Text(watchFolderName)
                        .foregroundStyle(settings.watchFolderPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose\u{2026}") { chooseWatchFolder() }
                        .controlSize(.small)
                }
            }
            Toggle("Auto-clean dropped recordings", isOn: watchEnabledBinding)
                .disabled(settings.watchFolderPath.isEmpty)
            Toggle("Remove fillers", isOn: $settings.watchRemoveFillers)
                .disabled(!settings.watchEnabled)
        } header: {
            Text("Watch Folder")
        } footer: {
            watchFooter.font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var watchFooter: some View {
        // The alarming states only make sense once the user has actually turned
        // watching on; until then keep the neutral "how it works" hint.
        if case .error(let message) = watchAgent.status {
            Text(message).foregroundStyle(.red)
        } else if settings.watchEnabled {
            switch watchAgent.status {
            case .requiresApproval:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Crisp in Login Items to start watching.")
                    Button("Open Login Items\u{2026}") { SMAppService.openSystemSettingsLoginItems() }
                        .controlSize(.small)
                }
            case .notFound:
                Text("The background helper wasn\u{2019}t found. Reinstall Crisp to enable watching.")
            default:
                Text("Crisp watches this folder in the background \u{2014} even when this window is closed \u{2014} and cleans any recording dropped in.")
            }
        } else {
            Text("Pick a folder, then turn on auto-clean. A cleaned copy is written beside each recording; your original is untouched.")
        }
    }

    private func chooseWatchFolder() {
        if let path = FolderPicker.choosePath(message: "Choose a folder to watch for new recordings.") {
            settings.watchFolderPath = path
        }
    }

    // MARK: - General: Software update

    /// The action row: a Check button (with inline result), the install prompt when
    /// an update is found, or progress while it downloads/installs. All three drive
    /// the same shared `Updater` the launch check and menu command use.
    @ViewBuilder private var updateRow: some View {
        switch updater.status {
        case .available(let release):
            LabeledContent {
                Button("Install & Relaunch") { Task { await updater.downloadAndInstall() } }
            } label: {
                Label("Update available \u{2014} \(release.displayVersion)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
            }
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updater.status == .downloading ? "Downloading update\u{2026}" : "Installing update\u{2026}")
                    .foregroundStyle(.secondary)
            }
        default:
            LabeledContent {
                switch updater.status {
                case .checking:
                    ProgressView().controlSize(.small)
                case .upToDate:
                    Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            } label: {
                Button("Check for Updates\u{2026}") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
            }
        }
    }

    /// Footer: a check error (if any), the disabled note for Dev, the last-checked
    /// time, or the default "checks at launch" line.
    @ViewBuilder private var updateFooter: some View {
        if case .failed(let message) = updater.status {
            Text(message).foregroundStyle(.red)
        } else if !Channel.current.updatesEnabled {
            Text("Automatic updates are off for this build.")
        } else if let date = updater.lastChecked {
            Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened)).")
        } else {
            Text("Crisp also checks automatically each time it launches.")
        }
    }

    @ViewBuilder private var softwareUpdateSection: some View {
        Section {
            LabeledContent("Version") {
                Text(versionString).foregroundStyle(.secondary)
            }
            updateRow
        } header: {
            Text("Software Update")
        } footer: {
            updateFooter.font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - General: Diagnostics + reset

    @ViewBuilder private var diagnosticsSection: some View {
        Section {
            LabeledContent("Logs") {
                Button("Reveal in Finder") { Diagnostics.revealLogs() }
                    .controlSize(.small)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Crisp keeps a daily log of each clean \u{2014} and anything that goes wrong \u{2014} in \(logsPathDisplay). If you hit a problem, share today\u{2019}s log.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var restoreDefaultsSection: some View {
        Section {
            Button("Restore Defaults") { settings.restoreDefaults() }
        } footer: {
            Text("Resets the cutting, encoding, output, captions, and backup options to their defaults. Your presets, speech model, performance, and automation (watch folder, menu bar) settings are left unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var logsPathDisplay: String {
        (Channel.current.logsDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Cutting slider row

    private func row(_ knob: Knob, _ value: Binding<Double>) -> some View {
        let readout = String(format: "%.\(knob.decimals)f", value.wrappedValue) + " " + knob.unit
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(knob.title)
                Spacer()
                Text(readout).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: knob.range, step: knob.step)
            Text(knob.help).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
