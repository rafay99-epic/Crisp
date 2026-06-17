import Foundation

/// `m:ss` for a duration in seconds (e.g. 65 → "1:05"). Used wherever the UI
/// shows clip lengths or time saved.
func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}
