import SwiftUI

/// The ⌘, Settings window. Edits the four numeric cutting knobs used by the
/// "Custom" strength; values persist to `~/.crisp*/config/settings.json`.
struct SettingsView: View {
    @Bindable var settings: EngineSettings

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
                Picker("Video format", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Hardware acceleration", isOn: $settings.hardwareEncoding)
                Text("Apple VideoToolbox \u{2014} faster, but software gives slightly better quality per file size.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Quality", selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Audio format", selection: $settings.audioCodec) {
                    ForEach(AudioCodec.allCases) { Text($0.label).tag($0.rawValue) }
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

            Section {
                Button("Restore Defaults") { settings.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
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
