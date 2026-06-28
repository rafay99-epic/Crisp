import SwiftUI
import AppKit
import CrispCore

/// Refuses to let Crisp quit or close its window while footage is being processed.
///
/// A clean re-encodes the user's video; interrupting it mid-write leaves a corrupt,
/// half-rendered output — the one thing the app must never do (philosophy #2, "never
/// lose the user's footage"). So while any in-process engine run is alive we hard-block
/// the graceful exit paths — ⌘Q, the Quit menu item, Dock ▸ Quit, logout/shutdown, and
/// the window's close button / ⌘W — and explain why instead of letting the action through.
/// The block lifts the instant the run returns, i.e. the moment the output (a cleaned
/// file, or the editor handoff's copy + FCPXML) is safely on disk — even before any
/// handoff to an external editor.
///
/// The escape hatch is intentional and unblockable: Force Quit / Activity Monitor send
/// SIGKILL, which no app can veto, so a user who truly must bail always can.
///
/// `busy` is read live from the app's existing run flags (`CleanModel.isRunning`,
/// `QuickDropModel.isBusy`) via `isBusyProbe`, so there's a single source of truth and no
/// parallel counter to drift. The probe is view-independent, so quitting is guarded even
/// if the main window was closed while a menu-bar Quick Clean runs.
///
/// Two enforcement mechanisms, because the two exit paths live at different layers:
/// - **Quit** routes through `applicationShouldTerminate` (an app-level chokepoint the
///   `AppDelegate` owns) — we cancel it and raise the explanatory sheet.
/// - **Window close** is a *window*-level decision. A `windowShouldClose` delegate would
///   be the obvious hook, but SwiftUI owns the `Window` scene's NSWindow delegate and
///   re-installs its own (clobbering ours, verified), so it can't be relied on. Instead we
///   toggle the window's `.closable` style mask: while busy the red close button greys out
///   and ⌘W's "Close" menu item disables — a native, unspoofable "you can't close this
///   right now," not subject to the delegate race.
@MainActor
@Observable
final class ProcessingGuard {
    static let shared = ProcessingGuard()
    private init() {}

    /// Wired by `CrispApp` to the live run flags. Default = never busy (so a probe-less
    /// build, e.g. a unit test, never blocks).
    @ObservationIgnored var isBusyProbe: () -> Bool = { false }

    /// The main window, captured by `MainWindowAttacher`, so we can toggle its closability.
    @ObservationIgnored weak var mainWindow: NSWindow?

    /// True while any in-process clean/render is running.
    var busy: Bool { isBusyProbe() }

    /// Drives the explanatory sheet. Set when a quit is refused; cleared when the user
    /// dismisses it or the work finishes.
    var showBlockedNotice = false

    /// Adopt the main window and bring its closability in line with the current state.
    func attach(_ window: NSWindow) {
        mainWindow = window
        syncClosable()
    }

    /// Grey out (busy) or restore (idle) the window's close button + ⌘W, so the user can't
    /// close the window out from under a running render. Idempotent; safe to call often.
    func syncClosable() {
        guard let window = mainWindow else { return }
        if busy {
            window.styleMask.remove(.closable)
        } else {
            window.styleMask.insert(.closable)
        }
    }

    /// Raise the "can't quit yet" notice and bring Crisp forward so the user sees why.
    /// When a visible window can host it, that's the SwiftUI sheet; when there isn't one —
    /// e.g. a menu-bar Quick Clean running with the main window closed — a standalone
    /// notice carries the refusal instead, so it's never silently swallowed.
    func refuse() {
        // `NSApp` is nil in a headless context (e.g. unit tests); only the running app
        // needs bringing forward so the user can see the notice.
        NSApp?.activate(ignoringOtherApps: true)
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            showBlockedNotice = true   // the SwiftUI sheet, hosted on the main window
        } else {
            presentWindowlessNotice()
        }
    }

    /// The fallback when the refusal can't ride the main window's sheet (it's closed): a
    /// standalone notice so a ⌘Q during a menu-bar Quick Clean is never silently ignored.
    /// The alert is modal, so — like the sheet, which auto-dismisses when work ends — we
    /// poll the busy state and abort the modal once the render finishes, otherwise a notice
    /// left untouched would keep the app pinned long after it was safe to quit.
    private func presentWindowlessNotice() {
        guard NSApp != nil else { return }   // headless: nothing to show, nothing to block
        let alert = NSAlert()
        alert.messageText = QuitGuardCopy.title
        alert.informativeText = QuitGuardCopy.body
        alert.addButton(withTitle: QuitGuardCopy.action)

        // Tear the alert down by itself once the render finishes. The timer must run in the
        // modal run-loop mode (`.common` covers it) — a default-mode timer never fires
        // while `runModal` owns the loop.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard self?.busy != true else { return }
            timer.invalidate()
            NSApp.abortModal()
        }
        RunLoop.main.add(timer, forMode: .common)
        alert.runModal()
        timer.invalidate()
    }
}

/// Shared copy for the two surfaces that explain a refused quit — the in-window SwiftUI
/// sheet and the windowless `NSAlert` fallback — so they never drift.
enum QuitGuardCopy {
    static let title = "Crisp is still working"
    static let body = "Quitting now could corrupt the video that's rendering. "
        + "You'll be able to quit as soon as it's finished.\n\n"
        + "Need to stop immediately? You can force quit from Activity Monitor."
    static let action = "Keep Cleaning"
}

/// Owns the app-level termination decision via `applicationShouldTerminate` — the single
/// chokepoint every graceful quit path funnels through (⌘Q, the Quit menu item, Dock ▸
/// Quit, logout/shutdown).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = AppInfo.logger("quit-guard")

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProcessingGuard.shared.busy else { return .terminateNow }
        log.info("quit refused — a clean is still rendering")
        ProcessingGuard.shared.refuse()
        return .terminateCancel
    }
}

/// A zero-size helper that captures the NSWindow hosting the main content and hands it to
/// the `ProcessingGuard` (which toggles its closability while busy). `busy` is an input so
/// SwiftUI re-runs `updateNSView` on every state transition — that's where we re-sync, in
/// case the window arrives after the run starts (e.g. reopened mid-render). We only touch
/// the main window; Settings/History are separate scenes and close freely.
struct MainWindowAttacher: NSViewRepresentable {
    let busy: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            ProcessingGuard.shared.attach(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-capture in case the window changed (reopen), then reflect the new busy state.
        if let window = nsView.window { ProcessingGuard.shared.mainWindow = window }
        ProcessingGuard.shared.syncClosable()
    }
}

/// The custom Crisp explanation shown when a quit is refused mid-render — an honest,
/// on-brand surface (one "Keep Cleaning" action, no "quit anyway"), not the system's
/// default termination dialog. Auto-dismisses the instant the work finishes.
private struct QuitBlockedModifier: ViewModifier {
    /// Live busy flag, passed in so the sheet can dismiss itself when the run ends.
    let isBusy: Bool
    @Bindable private var guardState = ProcessingGuard.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $guardState.showBlockedNotice) {
                QuitBlockedSheet { guardState.showBlockedNotice = false }
            }
            // The work finished while the notice was up — the user can quit now, so drop it.
            .onChange(of: isBusy) { _, busy in
                if !busy { guardState.showBlockedNotice = false }
            }
    }
}

private struct QuitBlockedSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scissors")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 6) {
                Text(QuitGuardCopy.title)
                    .font(.title3.weight(.semibold))
                Text(QuitGuardCopy.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(QuitGuardCopy.action, action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 360)
    }
}

extension View {
    /// Show the custom "can't quit mid-render" sheet, dismissing it when `isBusy` clears.
    func quitBlockedNotice(isBusy: Bool) -> some View {
        modifier(QuitBlockedModifier(isBusy: isBusy))
    }
}
