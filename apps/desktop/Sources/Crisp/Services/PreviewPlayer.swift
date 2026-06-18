import AVFoundation
import SwiftUI

/// Plays a cleaned file so the user can spot-check it before uploading — one at a
/// time, toggled from the queue row. Audio plays without a video window (a quick
/// listen is enough to trust the cut); it resets when playback ends.
@MainActor
@Observable
final class PreviewPlayer {
    /// The file currently playing, so rows can show the right play/stop state.
    private(set) var playingURL: URL?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ url: URL) {
        if playingURL == url { stop(); return }
        stop()
        let player = AVPlayer(url: url)
        self.player = player
        playingURL = url
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        player.play()
    }

    func stop() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        playingURL = nil
    }

    func isPlaying(_ url: URL) -> Bool { playingURL == url }
}
