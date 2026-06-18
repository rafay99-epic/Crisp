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
        case welcome, howItWorks, fillers, preferences, automate, done
    }

    private var steps: [Step] { Step.allCases }
    private var step: Step { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    content
                }
                .padding(.horizontal, 44)
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 600)
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
                    : "Crisp tightens up your screen recordings and talking-head videos — automatically cutting out long pauses and filler words to leave clean, snappy jump-cuts.")
            featureRow("checkmark.shield.fill", "Your footage is safe",
                       "Crisp never edits or deletes your original. It only ever writes a new cleaned copy beside it.")
            featureRow("rectangle.on.rectangle", "No quality loss",
                       "Cuts re-encode at the same resolution and frame rate — never downscaled.")

        case .howItWorks:
            header(symbol: "wand.and.stars", title: "Clean a video in seconds",
                   subtitle: "Three steps, and you’re done.")
            featureRow("film.stack", "Drop or choose a video",
                       "Drag a recording onto the window, or click “Choose video…”.")
            featureRow("slider.horizontal.3", "Pick how much to cut",
                       "Gentle through Very Aggressive — or Custom for full control.")
            featureRow("scissors", "Hit Clean",
                       "Crisp finds the silences and fillers and cuts them out, saving “name_cleaned.mp4”.")

        case .fillers:
            header(symbol: "waveform", title: "Pauses & filler words",
                   subtitle: "Crisp removes dead air, and can also strip the “um”s and “uh”s.")
            featureRow("waveform", "Pauses — always on",
                       "Detected from the real audio. Works out of the box, no setup.")
            featureRow("text.bubble.fill", "Filler words — optional",
                       "Turn on “Remove filler words” and Crisp downloads a one-time speech model. Pauses-only needs no download.")
            modelWidget

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
            watchSetup

        case .done:
            header(symbol: "checkmark.seal.fill", title: "You’re all set",
                   subtitle: "Everything’s ready. You can fine-tune cutting strength, the encoder, and more in Settings (⌘,), and reopen this guide any time from the Help menu.")
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
            settingRow("Hardware acceleration", "Faster encoding using Apple’s media engine.") {
                Toggle("", isOn: $settings.hardwareEncoding).labelsHidden().toggleStyle(.switch)
            }
            settingRow("Keep a backup of the original", "Copied aside before each clean — recommended.") {
                Toggle("", isOn: $settings.backupOriginal).labelsHidden().toggleStyle(.switch)
            }
        }
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to watch for new recordings."
        if panel.runModal() == .OK, let url = panel.url {
            settings.watchFolderPath = url.path
        }
    }

    // MARK: - Optional model download (filler step)

    @ViewBuilder private var modelWidget: some View {
        HStack(spacing: 10) {
            switch modelStore.state {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Speech model ready — filler removal is set up.").font(.callout)
            case .downloading(let fraction):
                ProgressView(value: fraction < 0 ? nil : fraction).frame(width: 130)
                Text(fraction < 0 ? "Downloading…" : "Downloading… \(Int(fraction * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
            case .verifying:
                ProgressView().controlSize(.small)
                Text("Verifying…").font(.callout).foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.callout).foregroundStyle(.secondary)
            default:
                Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                Text("Set up filler removal now (optional):").font(.callout).foregroundStyle(.secondary)
                Button("Download (~148 MB)") { modelStore.download() }.controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.tint.opacity(0.08))
    }

    // MARK: - Reusable pieces

    @ViewBuilder private func header(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            if symbol.isEmpty {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 84, height: 84)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 84, height: 84)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            }
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
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
                Button("Skip") { onboarding.finish() }
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
