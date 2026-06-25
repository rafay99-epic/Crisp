import SwiftUI

struct ContentView: View {
    @Bindable var bench: Bench
    @State private var threshold = 0.7

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView { content.padding(20) }
        }
    }

    // MARK: controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.title2).foregroundStyle(.tint)
                Text("FillerBench").font(.headline)
                Spacer()
                Picker("Split", selection: $bench.split) {
                    Text("test").tag("test")
                    Text("validation").tag("validation")
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
                Toggle("Quick", isOn: $bench.quick).toggleStyle(.checkbox)
                Button { bench.run() } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).disabled(bench.isRunning)
            }
            TextField("Research dir", text: $bench.researchDir)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: content states

    @ViewBuilder private var content: some View {
        if bench.isRunning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Scoring on held-out \(bench.split) data…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if let e = bench.errorText {
            Label(e, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        } else if let r = bench.report {
            results(r)
        } else {
            ContentUnavailableView("No results yet", systemImage: "chart.bar.xaxis",
                description: Text("Pick a split and hit Run to score the model on held-out test data."))
                .frame(minHeight: 320)
        }
    }

    // MARK: results

    @ViewBuilder private func results(_ r: Report) -> some View {
        let pt = r.sweep.first { abs($0.threshold - threshold) < 0.001 } ?? r.bestF1Threshold
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.dataset) · \(r.split)").font(.title2.bold())
                Text("\(r.nExamples) examples — \(r.nFiller) filler / \(r.nNonfiller) non-filler  ·  \(Int(r.speed.realtimeFactor))× real-time")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Text("Decision threshold").font(.headline)
                Spacer()
                Picker("", selection: $threshold) {
                    ForEach(r.sweep.map(\.threshold), id: \.self) { t in
                        Text(String(format: "%.1f", t)).tag(t)
                    }
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
            }

            HStack(spacing: 14) {
                MetricCard(title: "Precision", value: pt.precision,
                           hint: "of cuts, were real fillers", tint: .blue)
                MetricCard(title: "Recall", value: pt.recall,
                           hint: "of real fillers, were caught", tint: .green)
                MetricCard(title: "F1", value: pt.f1,
                           hint: "balance of both", tint: .purple)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What it wrongly cuts — false positives @ 0.5").font(.headline)
                ForEach(r.falsePositivesByClass) { FPRow(c: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()

            HStack(spacing: 14) {
                ForEach(r.recallByFiller) { rec in
                    VStack(spacing: 4) {
                        Text("“\(rec.label)”").font(.headline)
                        Text("\(Int(rec.recall * 100))% recall").foregroundStyle(.secondary)
                        Text("\(rec.n) clips").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14).cardBackground()
                }
            }
        }
    }
}

// MARK: - Pieces

private struct MetricCard: View {
    let title: String
    let value: Double
    let hint: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(hint).font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).cardBackground()
    }
}

private struct FPRow: View {
    let c: FPClass

    var body: some View {
        HStack(spacing: 10) {
            Text(c.label).frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4).fill(.orange)
                        .frame(width: max(2, geo.size.width * min(1, c.pct / 30)))
                }
            }
            .frame(height: 14)
            Text(String(format: "%.1f%%", c.pct))
                .frame(width: 56, alignment: .trailing)
                .font(.callout.monospacedDigit())
        }
    }
}

private extension View {
    func cardBackground() -> some View {
        padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
