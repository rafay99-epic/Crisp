import SwiftUI
import CrispCore

/// Live cut preview: analyze a video's audio once, then show — updating as the user
/// drags the cut knobs — the source waveform with the slices that would be removed
/// dimmed, plus how many pauses and how much time would be cut. Pauses only (filler
/// words also get removed during the real clean but need transcription to locate).
///
/// Previews the recipe the file will *actually* be cleaned with: if the queue row
/// has a preset, the controls seed from and apply to that preset; otherwise they use
/// the window's default recipe. The cut knobs run through the same
/// `Strength.parameters(using:)` mapping the real clean uses, so the preview can't
/// drift from the output.
struct PreviewSheet: View {
    let item: QueueItem
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings
    @Environment(\.dismiss) private var dismiss

    @State private var strength: Strength = .balanced
    @State private var pause = EngineConfig.defaults.pauseThreshold
    @State private var breathing = EngineConfig.defaults.breathingRoom
    @State private var minKeep = EngineConfig.defaults.minKeep

    /// The analysis orchestration (run/cache/cancel) lives in the service.
    @State private var analysis = PreviewModel()

    private var input: URL { item.url }
    private var isCustom: Bool { strength == .custom }

    /// The preset this row uses, if any — drives seeding, the label, and where Apply
    /// writes.
    private var preset: Preset? { settings.preset(withID: item.presetID) }

    // MARK: Effective cut parameters (via the real mapping — no duplicated logic)

    /// The exact cut parameters this preview represents, resolved through the same
    /// `Strength.parameters(using:)` path a real clean uses. Presets carry no custom
    /// silence floor, so they resolve against engine defaults; the global recipe uses
    /// the saved config. Only the local cut knobs are overlaid.
    private var effectiveParams: CleanParameters {
        var config = preset == nil ? settings.config : EngineConfig.defaults
        // Pause handling isn't a knob in this sheet, but the preview must still match
        // the render — carry the preset's mode (the global config already has it).
        if let preset {
            config.pauseMode = preset.pauseMode
            config.tightPause = preset.tightPause
        }
        config.pauseThreshold = pause
        config.breathingRoom = breathing
        config.minKeep = minKeep
        return strength.parameters(using: config)
    }

    private var computedPreview: CutPreview.Result? {
        guard let a = analysis.current else { return nil }
        let p = effectiveParams
        return CutPreview.compute(silences: a.silences, duration: a.duration,
                                  pause: p.pause, keepPause: p.keepPause, minKeep: p.minKeep,
                                  pauseMode: p.pauseMode, tightPause: p.tightPause)
    }

    var body: some View {
        // Compute the cut set once per render and feed both the waveform and stats.
        let result = computedPreview
        return VStack(alignment: .leading, spacing: 14) {
            header
            waveform(result)
            stats(result)
            controls
            footer
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: seedAndLoad)
        .onChange(of: strength) { reload() }   // a preset↔custom switch may change the floor
        .onDisappear { analysis.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Preview cuts").font(.headline)
            HStack(spacing: 6) {
                Text(input.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                if let preset {
                    Text("\u{00B7} preset \u{201C}\(preset.name)\u{201D}")
                        .foregroundStyle(.tint).lineLimit(1)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func waveform(_ result: CutPreview.Result?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4))
            if let a = analysis.current, !a.peaks.isEmpty {
                WaveformView(peaks: a.peaks, removed: mask(a, result))
                    .padding(10)
            } else if analysis.isAnalyzing {
                ProgressView("Analyzing\u{2026}").controlSize(.small)
            } else if let errorText = analysis.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).padding(8)
            }
        }
        .frame(height: 90)
    }

    private func mask(_ analysis: VideoAnalysis, _ result: CutPreview.Result?) -> [Bool] {
        guard let p = result else { return [] }
        return CutPreview.removedMask(keep: p.keep, duration: analysis.duration,
                                      bucketCount: analysis.peaks.count)
    }

    @ViewBuilder private func stats(_ result: CutPreview.Result?) -> some View {
        if let a = analysis.current, let p = result {
            let pct = a.duration > 0 ? Int((p.removedSeconds / a.duration) * 100) : 0
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                Text("\(p.pauseCount) pause\(p.pauseCount == 1 ? "" : "s") \u{00B7} would remove \(formatTime(p.removedSeconds))")
                    .contentTransition(.numericText())
                Text("(\(pct)% shorter)").foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .font(.callout)
            .animation(.snappy, value: p.removedSeconds)
        } else {
            Text("Pauses only \u{2014} filler words are also removed when you clean.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var controls: some View {
        Picker("How much to cut", selection: $strength) {
            ForEach(Strength.allCases) { Text($0.pickerLabel).tag($0) }
        }
        .pickerStyle(.segmented)

        if isCustom {
            knob("Pause threshold", value: $pause, range: 0.1...2.0, step: 0.05, unit: "s")
            knob("Breathing room", value: $breathing, range: 0...0.5, step: 0.01, unit: "s")
            knob("Minimum keep", value: $minKeep, range: 0...0.5, step: 0.01, unit: "s")
        } else {
            Text(strength.detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Pauses only \u{2014} fillers also removed on clean.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button(preset == nil ? "Use These Settings" : "Save to Preset") { apply() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func knob(_ title: String, value: Binding<Double>,
                      range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }

    // MARK: - Analysis

    private func seedAndLoad() {
        if let preset {
            strength = Strength(rawValue: preset.strength) ?? .custom
            pause = preset.pauseThreshold
            breathing = preset.breathingRoom
            minKeep = preset.minKeep
        } else {
            strength = model.strength
            pause = settings.pauseThreshold
            breathing = settings.breathingRoom
            minKeep = settings.minKeep
        }
        reload()
    }

    private func reload() {
        analysis.load(input: input, noiseDB: effectiveParams.noiseDB)
    }

    /// Apply the chosen recipe where it'll actually take effect: into the row's preset
    /// if it has one, otherwise the window's default recipe.
    private func apply() {
        if let pid = item.presetID, let idx = settings.presets.firstIndex(where: { $0.id == pid }) {
            settings.presets[idx].strength = strength.rawValue
            if isCustom {
                settings.presets[idx].pauseThreshold = pause
                settings.presets[idx].breathingRoom = breathing
                settings.presets[idx].minKeep = minKeep
            }
        } else {
            model.strength = strength
            if isCustom {
                settings.pauseThreshold = pause
                settings.breathingRoom = breathing
                settings.minKeep = minKeep
            }
        }
        dismiss()
    }
}
