import SwiftUI

/// The signature view: the file's actual audio as peak bars, with the slices Crisp
/// cut drawn dim and the kept audio in green. Built from the engine's waveform
/// summary, so it shows exactly what was (or would be) removed — honest, and
/// unmistakably Crisp. Shared by the finished queue row and the live cut preview.
struct WaveformView: View {
    let peaks: [Double]
    let removed: [Bool]

    var body: some View {
        Canvas { context, size in
            let n = peaks.count
            guard n > 0 else { return }
            let gap: CGFloat = n > 90 ? 0.5 : 1
            let barW = max(0.75, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let mid = size.height / 2
            for i in 0..<n {
                let x = CGFloat(i) * (barW + gap)
                let h = max(1.5, CGFloat(peaks[i]) * size.height)
                let rect = CGRect(x: x, y: mid - h / 2, width: barW, height: h)
                let isCut = i < removed.count && removed[i]
                let style: GraphicsContext.Shading = isCut
                    ? .color(.secondary.opacity(0.28))
                    : .color(.green)
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: style)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Audio waveform with removed sections dimmed")
    }
}
