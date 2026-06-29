import SwiftUI
import AppKit
import ServiceManagement
import CrispCore

/// First-run welcome flow — a short, paged tour that both explains Crisp and lets
/// the user set it up to their liking before they ever reach the main window.
/// Owns the whole window on first launch (the app stays out of the way until it's
/// done). Native: system materials, SF Symbols, a `.borderedProminent` action,
/// page dots. Re-openable from Help ▸ Welcome to Crisp.
struct OnboardingView: View {
    @Bindable var onboarding: OnboardingController
    @Bindable var modelStore: ModelStore
    @Bindable var settings: EngineSettings
    @Bindable var watchAgent: WatchAgentController
    @State private var index = 0

    private enum Step: CaseIterable {
        case welcome, capabilities, fidelity, howItWorks, fillers, preferences, automate, done
    }

    private var steps: [Step] { Step.allCases }
    private var step: Step { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        content
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    // Grow to fill the viewport so each step sits vertically centered
                    // — short steps no longer leave a void beneath them — while the
                    // tall steps (fillers, preferences) still scroll when they must.
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Divider()
            footer
        }
        // Fill and center within the shared app window — resizable and content-
        // centered, exactly like the main workspace. The min height is sized so the
        // busier steps (What Crisp removes, the model choice, automate) show in full
        // without the user having to scroll on first run; the window can still grow.
        // `.windowResizability(.contentMinSize)` (CrispApp) enforces this floor even
        // over a smaller restored/default frame.
        .frame(minWidth: 600, minHeight: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step content

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            header(symbol: "",
                   title: settings.hasExistingConfig ? "Welcome back to Crisp" : "Welcome to Crisp",
                   subtitle: settings.hasExistingConfig
                    ? "Your saved settings are preserved — nothing has changed. Here’s a quick tour of how everything works."
                    : "Crisp tightens up your screen recordings and talking-head videos — automatically cutting out long pauses and filler words for clean, snappy jump-cuts, plus repeated takes when you use the Whisper speech model.")
            featureRow("checkmark.shield.fill", "Your footage is safe",
                       "Crisp never edits or deletes your original. It only ever writes a new cleaned copy beside it.")
            featureRow("rectangle.on.rectangle", "No quality loss",
                       "Cuts re-encode at the same resolution and frame rate — never downscaled.")

        case .capabilities:
            header(symbol: "scissors", title: "What Crisp removes",
                   subtitle: "Three kinds of dead weight — found automatically, entirely on your Mac.")
            featureRow("pause.fill", "Long pauses",
                       "Dead air and the gaps between sentences, detected from the real audio.")
            featureRow("waveform", "Filler words",
                       "“Um”, “uh”, “hmm” and the like — caught by the on-device Whisper speech model, or an optional faster custom model.")
            featureRow("arrow.uturn.backward", "Repeated takes",
                       "Flub a line and immediately say it again? Crisp keeps the corrected take and cuts the flubbed one — the tedious edit you’d normally do by hand. Needs the Whisper speech model.",
                       badge: "New")

        case .fidelity:
            header(symbol: "dial.high.fill", title: "What Crisp preserves",
                   subtitle: "Cutting is only half the job. Crisp protects what makes your footage look right — automatically, and never downgrades it.")
            featureRow("speedometer", "Stays perfectly in sync",
                       "Screen recordings often vary their frame rate, which can drift audio out of sync after cutting. Crisp detects that and re-times them to a steady rate — ordinary footage is left exactly as it is.",
                       badge: "New")
            featureRow("paintpalette.fill", "Keeps your color and HDR",
                       "10-bit and HDR recordings stay 10-bit and HDR — Crisp matches your source’s color depth instead of silently flattening it to a washed-out copy.",
                       badge: "New")
            featureRow("shippingbox.fill", "Your format, your call",
                       "Export an MP4 with H.264 or HEVC, or a web-friendly WebM, and choose the audio quality and hardware encoding — Crisp keeps incompatible combinations from happening.")
            featureRow("film.stack", "Or hand the cuts to your editor",
                       "Prefer to finish in your own editor? Crisp can pass the cuts to DaVinci Resolve as a ready-to-edit timeline — no finished video to render, and every cut stays adjustable. Turn it on in the “Make it automatic” step.")
            Text("It all happens automatically on smart defaults — fine-tune any of it later in Settings (⌘,).")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

        case .howItWorks:
            header(symbol: "wand.and.stars", title: "Clean your videos in seconds",
                   subtitle: "Add as many as you like — Crisp cleans them as a queue.")
            featureRow("film.stack", "Add your videos",
                       "Drag recordings onto the window, or click “Choose videos…”. They line up in a queue you can reorder — the top one runs first.")
            featureRow("slider.horizontal.3", "Pick how much to cut",
                       "Set the default for the queue — Gentle through Very Aggressive, or Custom — and give any single file its own preset.")
            featureRow("waveform", "Preview the cuts first",
                       "Click Preview on any queued video to see exactly what Crisp will remove — and tune the strength live before you commit.")
            featureRow("scissors", "Clean the queue",
                       "Crisp cuts the silences and fillers from each one — several at once when your Mac can — and saves a cleaned copy of every original.")

        case .fillers:
            header(symbol: "waveform", title: "Choose a speech model",
                   subtitle: "Crisp detects filler words with a speech model that runs entirely on your Mac. Install one to finish setup — pauses are always removed either way.")
            modelChoice

        case .preferences:
            header(symbol: "slider.horizontal.3", title: "Make it yours",
                   subtitle: settings.hasExistingConfig
                    ? "These are your saved settings — adjust anything, or leave them as they are."
                    : "Set your defaults now — you can change any of this later in Settings (⌘,).")
            if settings.hasExistingConfig { detectedConfigBanner }
            preferences

        case .automate:
            header(symbol: "bolt.fill", title: "Make it automatic",
                   subtitle: "Crisp fits into the way you already work.")
            featureRow("cursorarrow.click.2", "Finder right-click",
                       "Right-click any video → Services → Clean with Crisp.")
            featureRow("square.stack.3d.up.fill", "Shortcuts",
                       "Add the “Clean with Crisp” action to any Shortcut or automation.")
            editorHandoffSetup
            menuBarSetup
            watchSetup

        case .done:
            header(symbol: "checkmark.seal.fill", title: "You’re all set",
                   subtitle: "Everything’s ready. You can fine-tune cutting strength, the encoder, and more in Settings (⌘,), and reopen this guide any time from the Help menu.")
            featureRow("clock.arrow.circlepath", "Find every clean in History",
                       "Open History (⌘Y) for a list of everything Crisp has cleaned — from the queue, the menu bar, Shortcuts, or the watch folder — to reveal or re-clean.")
        }
    }

    // MARK: - Detected existing config

    /// Shown only when the user arrived with a real saved configuration (see
    /// `EngineSettings.hasExistingConfig`). Brand-new users and anyone on the
    /// defaults never see this.
    private var detectedConfigBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your existing settings were detected").font(.headline)
                Text("Crisp kept your saved configuration — it’s already applied below. Nothing was reset.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Color.green.opacity(0.12))
    }

    // MARK: - Configuration: preferences

    @ViewBuilder private var preferences: some View {
        VStack(spacing: 12) {
            settingRow("Output quality", "Higher quality means larger files.") {
                Picker("", selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 150)
            }
            settingRow("Output format", "“Same as input” keeps each video’s container.") {
                Picker("", selection: $settings.outputContainer) {
                    ForEach(OutputContainer.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 150)
            }
            settingRow("Save cleaned files to", outputLocationSubtitle) {
                HStack(spacing: 6) {
                    if !settings.outputDirectory.isEmpty {
                        Button("Reset") { settings.outputDirectory = "" }.controlSize(.small)
                    }
                    Button(settings.outputDirectory.isEmpty ? "Choose…" : "Change…") { chooseOutputFolder() }
                        .controlSize(.small)
                }
            }
            settingRow("Hardware acceleration", "Faster encoding using Apple’s media engine.") {
                Toggle("", isOn: $settings.hardwareEncoding).labelsHidden().toggleStyle(.switch)
            }
            settingRow("Keep a backup of the original", "Copied aside before each clean — recommended.") {
                Toggle("", isOn: $settings.backupOriginal).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var outputLocationSubtitle: String {
        settings.outputDirectory.isEmpty
            ? "Saved next to the source video (the default)."
            : "Saved to " + (settings.outputDirectory as NSString).abbreviatingWithTildeInPath
    }

    private func chooseOutputFolder() {
        if let path = FolderPicker.choosePath(message: "Choose where cleaned videos are saved (e.g. a NAS).") {
            settings.outputDirectory = path
        }
    }

    // MARK: - Configuration: editor handoff

    @ViewBuilder private var editorHandoffSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack").font(.title3).foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send to a video editor").font(.headline)
                    Text("Prefer to finish in your own editor? Crisp finds the cuts and hands them over as a ready-to-edit timeline — no rendering, so it’s done in seconds. You polish in the editor.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let editor = EditorDetector.resolve() {
                Toggle("Send my cuts to \(editor.name)", isOn: $settings.exportToEditor)
                    .toggleStyle(.switch)
            } else {
                Text("Install DaVinci Resolve (the free version works great) and Crisp can send your cuts straight to it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.tint.opacity(0.08))
    }

    // MARK: - Configuration: menu bar

    @ViewBuilder private var menuBarSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle").font(.title3).foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Bar").font(.headline)
                    Text("Drop a video on Crisp’s menu-bar icon to clean it with your default recipe — without opening this window.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Toggle("Show Crisp in the menu bar", isOn: $settings.menuBarEnabled)
                .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.tint.opacity(0.08))
    }

    // MARK: - Configuration: watch folder

    private var watchEnabledBinding: Binding<Bool> {
        Binding(get: { settings.watchEnabled },
                set: { on in settings.watchEnabled = on; watchAgent.setEnabled(on) })
    }

    @ViewBuilder private var watchSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape").font(.title3).foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Folder").font(.headline)
                    Text("Auto-clean anything dropped into a folder — even when Crisp is closed.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(settings.watchFolderPath.isEmpty
                     ? "No folder chosen"
                     : (settings.watchFolderPath as NSString).abbreviatingWithTildeInPath)
                    .font(.callout)
                    .foregroundStyle(settings.watchFolderPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Choose\u{2026}") { chooseWatchFolder() }.controlSize(.small)
            }
            Toggle("Auto-clean dropped recordings", isOn: watchEnabledBinding)
                .toggleStyle(.switch)
                .disabled(settings.watchFolderPath.isEmpty)
            if settings.watchEnabled, watchAgent.status == .requiresApproval {
                Text("Allow Crisp in System Settings ▸ Login Items to start watching.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.tint.opacity(0.08))
    }

    private func chooseWatchFolder() {
        if let path = FolderPicker.choosePath(message: "Choose a folder to watch for new recordings.") {
            settings.watchFolderPath = path
        }
    }

    // MARK: - Speech model choice (mandatory — gates the model step)

    /// True once the selected model is on disk and verified. Onboarding can't move
    /// past the model step until this holds (a model is required for filler removal).
    private var modelReady: Bool { modelStore.state.isReady }

    @ViewBuilder private var modelChoice: some View {
        VStack(spacing: 10) {
            ForEach(ModelCatalog.all) { spec in
                modelOption(spec)
            }
            ModelInstallControl(store: modelStore)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(.tint.opacity(0.08))
        }
    }

    private func modelOption(_ spec: ModelSpec) -> some View {
        let selected = settings.selectedModelID == spec.id
        return Button { selectModel(spec) } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(spec.displayName).font(.headline)
                        if spec.recommended {
                            Text("Recommended")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.tint.opacity(0.18)))
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(spec.summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(spec.approxSizeText).font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(selected ? AnyShapeStyle(.tint.opacity(0.12))
                                      : AnyShapeStyle(.quaternary.opacity(0.25)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.tint.opacity(selected ? 0.5 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(modelStore.state.isBusy)   // don't switch mid-download
    }

    /// Select a model: persist the choice and retarget the store (which rechecks
    /// disk, so picking an already-installed model is instantly ready again).
    private func selectModel(_ spec: ModelSpec) {
        guard settings.selectedModelID != spec.id else { return }
        settings.selectedModelID = spec.id
        modelStore.use(spec)   // synchronous: closes the gate immediately, then rechecks disk
    }

    /// "Skip" still routes through the mandatory model step until one is installed —
    /// a returning user who already has a model can leave immediately.
    private func skip() {
        if modelReady {
            onboarding.finish()
        } else {
            withAnimation(.snappy) { index = steps.firstIndex(of: .fillers) ?? index }
        }
    }

    // MARK: - Reusable pieces

    @ViewBuilder private func header(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            heroIcon(symbol)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }

    /// The step's mark. The welcome/done bookends show the real app icon — the app's
    /// own identity — while topic steps use an accent SF Symbol on the same tinted,
    /// rounded, continuous-corner surface the rest of the UI is built from. Sized to
    /// sit a notch above the title, never a heavy dark tile.
    @ViewBuilder private func heroIcon(_ symbol: String) -> some View {
        if symbol.isEmpty {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 76, height: 76)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.tint.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.tint.opacity(0.30), lineWidth: 1)
                        )
                }
                .accessibilityHidden(true)
        }
    }

    /// A feature row; pass `badge` to show a small accent capsule (e.g. "New") beside
    /// the title — same style as the "Recommended" tag on the model options.
    private func featureRow(_ symbol: String, _ title: String, _ detail: String,
                            badge: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if let badge {
                        Text(badge.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.tint.opacity(0.18)))
                            .foregroundStyle(.tint)
                    }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }

    private func settingRow<Control: View>(_ title: String, _ subtitle: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if index > 0 {
                Button("Back") { withAnimation(.snappy) { index -= 1 } }.buttonStyle(.link)
            } else {
                Button("Skip") { skip() }
                    .buttonStyle(.link).keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(isLast ? "Get Started" : "Continue") {
                if isLast { onboarding.finish() } else { withAnimation(.snappy) { index += 1 } }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            // A speech model is required — the model step can't be passed until one
            // is installed (a returning user's model is already ready, so no friction).
            .disabled(step == .fillers && !modelReady)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
