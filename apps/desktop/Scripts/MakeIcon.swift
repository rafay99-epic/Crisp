// Renders the Crisp app icon (1024x1024 PNG) — run by build.sh, not part of the
// app. The mark: an audio waveform with a clean "cut" gap in the middle, on a
// dark gradient squircle — the app trims audio/video, so the icon shows a
// waveform with a piece sliced out.
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
// Second arg picks the channel: "nightly" and "dev" recolor the waveform and
// stamp a badge so the Dock instantly distinguishes them from Stable.
let channel = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "stable"
// Third arg "glyph" renders just the waveform + badge on a transparent canvas —
// the foreground layer of the macOS 26 layered icon (.icon → Assets.car), where
// the system supplies the squircle, background fill, and dark/tinted treatments.
let glyphOnly = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "glyph"
func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
let accent: NSColor
let badgeLabel: String?
switch channel {
case "nightly":
    accent = rgb(0xff, 0x9f, 0x0a)  // amber
    badgeLabel = "NIGHTLY"
case "dev":
    accent = rgb(0xbf, 0x5a, 0xf2)  // purple
    badgeLabel = "DEV"
default:
    accent = rgb(0x0a, 0x84, 0xff)  // system blue
    badgeLabel = nil
}
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824x824 squircle centered on the 1024 canvas.
let inset: CGFloat = 100
let box = NSRect(x: inset, y: inset, width: 824, height: 824)
let radius: CGFloat = 185
let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

if glyphOnly {
    // The layered icon's mask covers the full 1024 canvas (no margins), so scale
    // the 824-box geometry up around the center to keep the same visual weight.
    let scale = 1024.0 / box.width
    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 512)
    transform.scale(by: scale)
    transform.translateX(by: -512, yBy: -512)
    transform.concat()
} else {
    // Soft drop shadow like system icons.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Dark gradient fill (linear-gradient(160deg, #2a2a2e, #161618)).
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    NSGradient(
        starting: NSColor(calibratedRed: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2e / 255.0, alpha: 1),
        ending: NSColor(calibratedRed: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    )?.draw(in: box, angle: -70)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Hairline border (1px rgba(255,255,255,0.12)).
    let borderWidth: CGFloat = 12
    let borderPath = NSBezierPath(
        roundedRect: box.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
        xRadius: radius - borderWidth / 2, yRadius: radius - borderWidth / 2
    )
    borderPath.lineWidth = borderWidth
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    borderPath.stroke()
}

// Waveform: a symmetric row of rounded vertical bars centered in the squircle,
// with a clean gap in the middle (the "cut"). Heights are a fixed pattern so
// renders are deterministic.
let barHeights: [CGFloat] = [
    0.30, 0.52, 0.74, 0.95, 0.66, 0.40,   // left cluster
    0.40, 0.66, 0.95, 0.74, 0.52, 0.30,   // right cluster (mirror)
]
let gapAfterIndex = 5                      // gap sits between the two clusters
let region = box.insetBy(dx: 150, dy: 0)
let centerY = box.midY
let maxBarHeight = box.height * 0.42
let count = barHeights.count
let gapWidth: CGFloat = 64
let slot = (region.width - gapWidth) / CGFloat(count)
let barWidth = slot * 0.46

accent.setFill()
var x = region.minX
for (index, h) in barHeights.enumerated() {
    let height = max(barWidth, maxBarHeight * h)
    let barRect = NSRect(x: x + (slot - barWidth) / 2, y: centerY - height / 2, width: barWidth, height: height)
    NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += slot
    if index == gapAfterIndex { x += gapWidth }
}

// Two soft cut-edges framing the gap.
let gapCenterX = region.minX + slot * CGFloat(gapAfterIndex + 1) + gapWidth / 2
NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
for dx in [-gapWidth / 2 - 4, gapWidth / 2 + 4] as [CGFloat] {
    let edge = NSBezierPath()
    edge.move(to: NSPoint(x: gapCenterX + dx, y: centerY - maxBarHeight * 0.62))
    edge.line(to: NSPoint(x: gapCenterX + dx, y: centerY + maxBarHeight * 0.62))
    edge.lineWidth = 5
    edge.lineCapStyle = .round
    edge.stroke()
}

// Channel badge: a pill near the bottom of the squircle.
if let badgeLabel {
    let label = badgeLabel as NSString
    let font = NSFont.systemFont(ofSize: badgeLabel.count > 3 ? 84 : 118, weight: .heavy)
    let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = label.size(withAttributes: textAttrs)
    let padX: CGFloat = 56, padY: CGFloat = 22
    let badgeW = textSize.width + padX * 2
    let badgeH = textSize.height + padY * 2
    let badgeRect = NSRect(x: box.midX - badgeW / 2, y: box.minY + 60, width: badgeW, height: badgeH)
    let badge = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
    accent.setFill()
    badge.fill()
    NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
    badge.lineWidth = 6
    badge.stroke()
    label.draw(at: NSPoint(x: badgeRect.midX - textSize.width / 2,
                           y: badgeRect.midY - textSize.height / 2), withAttributes: textAttrs)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
