import SwiftUI
import AVFoundation
import CrispCore

/// Review & edit cuts before cleaning: watch the source video, see every detected
/// cut on a timeline, toggle the ones you want to keep, preview the result, then
/// clean to exactly that keep-list (the engine renders it directly — no re-detection).
///
/// Reuses the same analysis + cut math as the live preview (`AnalysisRunner` +
/// `CutPreview`), so what you see is what gets rendered. Filler-word cuts aren't
/// shown here (they need transcription); this is the pause/structure editor.
struct ReviewSheet: View {
    let item: QueueItem
    @Bindable var model: CleanModel
    @Bindable var settings: EngineSettings
    @Environment(\.dismiss) private var dismiss

    @State private var review = ReviewModel()

    /// The recipe this file would actually clean with — its preset, or the window's
    /// default — so the detected cuts match a normal clean. (Only the cut knobs +
    /// silence floor matter for detection.)
    private var params: CleanParameters {
        if let preset = settings.preset(withID: item.presetID) {
            return preset.parameters(exportToEditor: settings.exportToEditor)
        }
        return model.strength.parameters(using: settings.config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            playerArea
            if review.isLoading {
                loading
            } else if let errorText = review.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            } else {
                timelineSection
                stats
            }
            footer
        }
        .padding(20)
        .frame(width: 660, height: 600)
        .onAppear { review.load(url: item.url, params: params) }
        .onDisappear { review.stop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Review & edit cuts").font(.headline)
            Text(item.url.lastPathComponent)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    // MARK: - Player

    private var playerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black)
            PlayerLayerView(player: review.player)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            // Big play/pause affordance over the video.
            Button(action: review.togglePlay) {
                Image(systemName: review.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
                    .opacity(review.isPlaying ? 0 : 1)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!review.isPlaying)
        }
        .frame(height: 300)
        .onTapGesture { review.togglePlay() }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Finding cuts\u{2026}").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: review.togglePlay) {
                    Image(systemName: review.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(review.isPlaying ? "Pause" : "Play")
                Text("\(formatTime(review.currentTime)) / \(formatTime(review.duration))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Toggle("Preview result", isOn: $review.previewResult)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Skip the removed parts during playback")
            }
            CutTimeline(review: review)
                .frame(height: 46)
            HStack(spacing: 12) {
                Text("Tap a red cut to keep it \u{00B7} tap the bar to scrub")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Remove all") { review.enableAllCuts(true) }
                    .controlSize(.small).disabled(review.cuts.allSatisfy(\.enabled))
                Button("Keep all") { review.enableAllCuts(false) }
                    .controlSize(.small).disabled(!review.hasCuts)
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        let pct = review.duration > 0 ? Int((review.removedSeconds / review.duration) * 100) : 0
        return HStack(spacing: 6) {
            Image(systemName: "scissors")
            Text("\(review.enabledCutCount) cut\(review.enabledCutCount == 1 ? "" : "s") \u{00B7} would remove \(formatTime(review.removedSeconds))")
                .contentTransition(.numericText())
            Text("(\(pct)% shorter)").foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .font(.callout)
        .animation(.snappy, value: review.removedSeconds)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Renders exactly these segments \u{2014} no re-detection.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Clean with These Cuts") { cleanWithEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(review.isLoading || review.errorText != nil || !review.hasCuts)
        }
    }

    private func cleanWithEdits() {
        let keep = review.keep
        let id = item.id
        let parameters = params
        Task { await model.cleanReviewed(id, keep: keep, parameters: parameters) }
        dismiss()
    }
}

/// The editable cut bar: kept stretches in green, removed cuts in red. A single
/// drag/tap gesture handles both jobs — a real drag (or a tap on a kept area) scrubs
/// the playhead; a tap on a cut toggles whether it's removed.
private struct CutTimeline: View {
    @Bindable var review: ReviewModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(review.duration, 0.001)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)

                // Kept stretches (everything not removed) in green. Keep ranges are
                // non-overlapping, so the range value is a stable identity (index-based
                // ids churn as cuts toggle, causing SwiftUI diffing artifacts).
                ForEach(review.keep, id: \.self) { range in
                    rect(start: range.lowerBound, end: range.upperBound, width: w, dur: dur)
                        .fill(.green.opacity(0.7))
                }
                // Enabled cuts in red, with a thin outline so a disabled cut (which
                // now reads as kept/green) is still discoverable by its border.
                ForEach(review.cuts) { cut in
                    rect(start: cut.start, end: cut.end, width: w, dur: dur)
                        .fill(cut.enabled ? AnyShapeStyle(.red.opacity(0.65)) : AnyShapeStyle(.clear))
                        .overlay(
                            rect(start: cut.start, end: cut.end, width: w, dur: dur)
                                .stroke(.primary.opacity(cut.enabled ? 0 : 0.4),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        )
                }

                // Playhead.
                Rectangle().fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 1)
                    .offset(x: CGFloat(review.currentTime / dur) * w - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // A real horizontal drag scrubs.
                        if abs(value.translation.width) > 4 {
                            review.seek(to: time(at: value.location.x, width: w, dur: dur))
                        }
                    }
                    .onEnded { value in
                        let t = time(at: value.location.x, width: w, dur: dur)
                        if abs(value.translation.width) <= 4 {
                            // A tap: toggle a cut if one is under the finger, else scrub.
                            if let cut = review.cuts.first(where: { t >= $0.start && t <= $0.end }) {
                                review.toggleCut(cut.id)
                            } else {
                                review.seek(to: t)
                            }
                        } else {
                            review.seek(to: t)
                        }
                    }
            )
        }
    }

    private func rect(start: Double, end: Double, width: CGFloat, dur: Double) -> Path {
        let x = CGFloat(start / dur) * width
        let w = max(2, CGFloat((end - start) / dur) * width)
        return Path(roundedRect: CGRect(x: x, y: 4, width: w, height: 38), cornerRadius: 4)
    }

    private func time(at x: CGFloat, width: CGFloat, dur: Double) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(dur, Double(x / width) * dur))
    }
}

/// A thin AppKit `AVPlayerLayer` host — plays the video with no built-in controls,
/// so the review timeline owns scrubbing and the skip-cut preview entirely.
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
