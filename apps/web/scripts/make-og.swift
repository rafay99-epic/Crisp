// Renders the 1200x630 social share card → public/og.png (the image every
// Open Graph / Twitter link preview uses). Run once and commit the PNG; rerun
// only when the wordmark/tagline changes:
//   swift apps/web/scripts/make-og.swift apps/web/public/og.png
// Mirrors the app icon's visual language (crisp/waveform-with-cut on a dark
// gradient) so the site, the app, and the share card all read as one product.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "og.png"
let W = 1200, H = 630

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    // sRGB (not calibrated) so pixels match the intended hex in the deviceRGB bitmap.
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let accent = rgb(10, 132, 255) // --color-accent
let accentBright = rgb(125, 192, 255) // top of the blue gradient

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: W, height: H)

// Background — the site's near-black canvas with a faint diagonal lift.
NSGradient(starting: rgb(15, 15, 21), ending: rgb(7, 7, 10))?.draw(in: canvas, angle: -70)

// Soft blue glow behind the mark.
NSGraphicsContext.current?.saveGraphicsState()
NSBezierPath(rect: canvas).addClip()
NSGradient(colors: [accent.withAlphaComponent(0.20), accent.withAlphaComponent(0)])?
    .draw(fromCenter: NSPoint(x: 600, y: 470), radius: 0,
          toCenter: NSPoint(x: 600, y: 470), radius: 360, options: [])
NSGraphicsContext.current?.restoreGraphicsState()

// Waveform with a clean cut in the middle — the product's signature mark.
let heights: [CGFloat] = [0.35, 0.55, 0.80, 1.0, 0.70, 0.45, 0.45, 0.70, 1.0, 0.80, 0.55, 0.35]
let gapAfter = 5
let bandW: CGFloat = 560, bandCenterX: CGFloat = 600, bandCenterY: CGFloat = 468
let maxBar: CGFloat = 150, gap: CGFloat = 46
let slot = (bandW - gap) / CGFloat(heights.count)
let barW = slot * 0.42
var x = bandCenterX - bandW / 2
for (i, h) in heights.enumerated() {
    let bh = max(barW, maxBar * h)
    let r = NSRect(x: x + (slot - barW) / 2, y: bandCenterY - bh / 2, width: barW, height: bh)
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).addClip()
    NSGradient(starting: accentBright, ending: accent)?.draw(in: r, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    x += slot
    if i == gapAfter { x += gap }
}
// Two hairline cut edges framing the gap.
let gapX = bandCenterX
NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
for dx in [-gap / 2 - 3, gap / 2 + 3] as [CGFloat] {
    let e = NSBezierPath()
    e.move(to: NSPoint(x: gapX + dx, y: bandCenterY - maxBar * 0.6))
    e.line(to: NSPoint(x: gapX + dx, y: bandCenterY + maxBar * 0.6))
    e.lineWidth = 4
    e.lineCapStyle = .round
    e.stroke()
}

// Centered text helper.
func drawCentered(_ s: String, font: NSFont, color: NSColor, baselineY: CGFloat, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking]
    let str = s as NSString
    let size = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: (CGFloat(W) - size.width) / 2, y: baselineY), withAttributes: attrs)
}

drawCentered("Crisp", font: .systemFont(ofSize: 132, weight: .bold),
             color: .white, baselineY: 232, tracking: -3)
drawCentered("Remove filler words and dead air — automatically.",
             font: .systemFont(ofSize: 33, weight: .medium),
             color: NSColor(calibratedWhite: 1, alpha: 0.72), baselineY: 168)
drawCentered("NATIVE MACOS  ·  100% LOCAL  ·  APPLE SILICON",
             font: .systemFont(ofSize: 20, weight: .semibold),
             color: accentBright.withAlphaComponent(0.85), baselineY: 96, tracking: 3)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
