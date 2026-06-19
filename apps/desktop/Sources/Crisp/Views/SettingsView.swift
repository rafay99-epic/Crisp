import SwiftUI
import AppKit
import ServiceManagement
import CrispCore

/// The ⌘, Settings window. Edits the four numeric cutting knobs used by the
/// "Custom" strength; values persist to `~/.crisp*/config/settings.json`.
struct SettingsView: View {
    @Bindable var settings: EngineSettings
    @Bindable var updater: Updater
    @Bindable var watchAgent: WatchAgentController
    @Bindable var modelStore: ModelStore
    @Bindable var model: CleanModel

    @State private var newPresetName = ""
    @State private var snapshot = SystemProbe.snapshot()

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

    /// Describes one slider row (keeps the row builder to a single argument).
    private struct Knob {
        let title: String
        let help: String
        let unit: String
        let range: ClosedRange<Double>
        let step: Double
        var decimals: Int = 2
    }

    var body: some View {
        Form {
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
            } header: {
                Text("Encoding")
            } footer: {
                Text("Applied to every clean. Cuts are always re-encoded, so these set the output quality.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            speechModelSection

            presetsSection

            performanceSection

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

            watchSection

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

            Section {
                Button("Restore Defaults") { settings.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onAppear { watchAgent.refresh(); snapshot = SystemProbe.snapshot() }
    }

    // MARK: - Speech model

    /// Switching the active model persists the choice and retargets the store, which
    /// rechecks disk (so picking an already-installed model is instantly ready).
    private var activeModelBinding: Binding<String> {
        Binding(get: { settings.selectedModelID },
                set: { id in
                    settings.selectedModelID = id
                    modelStore.use(ModelCatalog.spec(id: id))
                })
    }

    @ViewBuilder private var speechModelSection: some View {
        Section {
            Picker("Model", selection: activeModelBinding) {
                ForEach(ModelCatalog.all) { Text($0.displayName).tag($0.id) }
            }
            // Don't switch mid-download, or mid-clean (the running clean already
            // locked in its model — switching would only mislead).
            .disabled(modelStore.state.isBusy || model.isRunning)
            Text(modelStore.spec.summary)
                .font(.caption).foregroundStyle(.secondary)
            ModelInstallControl(store: modelStore, allowRemove: true, removeDisabled: model.isRunning)
        } header: {
            Text("Speech model")
        } footer: {
            Text("Used to find filler words. Larger models catch more fillers and place cuts more precisely, but download and run slower. Pauses are detected from the audio either way.")
                .font(.caption).foregroundStyle(.secondary)
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

    // MARK: - Output location

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

    // MARK: - Watch folder

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
