import SwiftUI
import CrispCore

/// Live cut preview: analyze a video's audio once, then show — updating as the user
/// drags the cut knobs — the source waveform with the slices that would be removed
/// dimmed, plus how many pauses and how much time would be cut. Pauses only (filler
/// words also get removed during the real clean but need transcription to locate).
/// "Use these settings" applies the choice to the default recipe.
struct PreviewSheet: View {
    let input: URL
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings
    @Environment(\.dismiss) private var dismiss

    @State private var strength: Strength = .balanced
    @State private var pause = EngineConfig.defaults.pauseThreshold
    @State private var breathing = EngineConfig.defaults.breathingRoom
    @State private var minKeep = EngineConfig.defaults.minKeep

    @State private var analysesByNoise: [Int: VideoAnalysis] = [:]
    @State private var current: VideoAnalysis?
    @State private var isAnalyzing = false
    @State private var errorText: String?
    @State private var analysisTask: Task<Void, Never>?

    // MARK: Effective knobs for the current selection

    private var isCustom: Bool { strength == .custom }
    private var effPause: Double { isCustom ? pause : strength.pause }
    private var effKeep: Double { isCustom ? breathing : strength.keepPause }
    private var effMinKeep: Double { isCustom ? minKeep : EngineConfig.defaults.minKeep }
    /// Presets use the default floor; Custom uses the saved silence floor. Only this
    /// changing forces a re-analysis (everything else recomputes locally).
    private var effNoise: Double { isCustom ? settings.silenceFloorDB : EngineConfig.defaults.silenceFloorDB }

    private var preview: CutPreview.Result? {
        guard let a = current else { return nil }
        return CutPreview.compute(silences: a.silences, duration: a.duration,
                                  pause: effPause, keepPause: effKeep, minKeep: effMinKeep)
    }

    private var removedMask: [Bool] {
        guard let a = current, let p = preview else { return [] }
        return CutPreview.removedMask(keep: p.keep, duration: a.duration, bucketCount: a.peaks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            waveform
            stats
            controls
            footer
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: seedAndLoad)
        .onChange(of: strength) { reload() }   // a preset↔custom switch may change the floor
        .onDisappear { analysisTask?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Preview cuts").font(.headline)
            Text(input.lastPathComponent)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var waveform: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4))
            if let a = current, !a.peaks.isEmpty {
                WaveformView(peaks: a.peaks, removed: removedMask)
                    .padding(10)
            } else if isAnalyzing {
                ProgressView("Analyzing\u{2026}").controlSize(.small)
            } else if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).padding(8)
            }
        }
        .frame(height: 90)
    }

    @ViewBuilder private var stats: some View {
        if let a = current, let p = preview {
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
            Button("Use These Settings") { apply() }
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
        strength = model.strength
        pause = settings.pauseThreshold
        breathing = settings.breathingRoom
        minKeep = settings.minKeep
        reload()
    }

    private func reload() {
        let noise = effNoise
        let key = Int(noise.rounded())
        if let cached = analysesByNoise[key] {
            current = cached
            return
        }
        analysisTask?.cancel()
        isAnalyzing = true
        errorText = nil
        current = nil
        analysisTask = Task {
            do {
                let analysis = try await AnalysisRunner().analyze(input: input, noiseDB: noise)
                if Task.isCancelled { return }
                analysesByNoise[key] = analysis
                current = analysis
                isAnalyzing = false
            } catch is CancellationError {
                // Superseded or dismissed — leave state to the newer load.
            } catch {
                if Task.isCancelled { return }
                errorText = "Couldn\u{2019}t analyze this video."
                isAnalyzing = false
            }
        }
    }

    private func apply() {
        model.strength = strength
        if isCustom {
            settings.pauseThreshold = pause
            settings.breathingRoom = breathing
            settings.minKeep = minKeep
        }
        dismiss()
    }
}
