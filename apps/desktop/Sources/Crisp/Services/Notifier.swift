import AppKit
import UserNotifications
import CrispCore

/// System notifications for finished batches. The point of a queue is to walk away
/// while it runs, so Crisp pings you when it's done — but only if you've switched
/// to another app (no need to notify what you're already watching).
@MainActor
enum Notifier {
    /// Ask once, at launch. Denial is fine — posting simply no-ops.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func batchFinished(cleaned: Int, savedSeconds: Double, failed: Int) {
        guard !NSApp.isActive else { return }      // they're looking at it — no ping needed
        let content = UNMutableNotificationContent()
        content.title = cleaned == 1 ? "Cleaned 1 video" : "Cleaned \(cleaned) videos"
        var body = "Removed \(formatTime(savedSeconds)) of pauses & fillers."
        if failed > 0 {
            body += failed == 1 ? " 1 couldn\u{2019}t be cleaned." : " \(failed) couldn\u{2019}t be cleaned."
        }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
