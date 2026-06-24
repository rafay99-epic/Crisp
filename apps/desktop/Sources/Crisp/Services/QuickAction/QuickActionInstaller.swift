import AppKit
import CrispCore

/// Installs the Finder **"Clean with Crisp"** Quick Action — an Automator
/// workflow dropped into `~/Library/Services/`. We use a workflow (run by Apple's
/// own `WorkflowServiceRunner`) rather than an app-vended `NSServices` entry
/// because macOS suppresses Services from ad-hoc/unsigned apps, which Crisp is.
/// The workflow just shells out to the bundled `CrispClean` CLI, so the actual
/// clean runs through the same `QuickClean` path as everything else.
///
/// Reinstalled on every launch (cheap, idempotent) so it always points at the
/// current app location and updates if the command changes.
@MainActor
enum QuickActionInstaller {
    /// `~/Library/Services/Clean with <Channel>.workflow` — per channel so the
    /// three installs don't collide.
    private static var workflowURL: URL {
        let services = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
        return services.appendingPathComponent("Clean with \(Channel.current.displayName).workflow",
                                                isDirectory: true)
    }

    /// Absolute path to the bundled cleaner the workflow invokes.
    private static var cleanerPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CrispClean").path
    }

    /// POSIX single-quote a string for embedding in the shell command: wrap in single
    /// quotes (which suppress *all* expansion) and rewrite any embedded `'` as `'\''`
    /// (close, escaped quote, reopen). Defense-in-depth — the only value spliced into
    /// the command is our own bundle path (no remote attacker controls it), but
    /// single-quoting means even a pathological install location (a folder literally
    /// named with `$(…)` or a backtick) can't expand. The selected files are NOT
    /// spliced here; they arrive at runtime as separate, already-quoted `"$@"` args.
    private static func singleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func install() {
        let command = "\(singleQuoted(cleanerPath)) \"$@\""
        let contents = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        let docURL = contents.appendingPathComponent("document.wflow")
        let infoURL = contents.appendingPathComponent("Info.plist")

        // Skip the rewrite when the installed workflow already targets this exact
        // command — avoids churning the Services database on every launch.
        if let existing = try? String(contentsOf: docURL, encoding: .utf8), existing.contains(command) {
            return
        }

        do {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try infoPlist().write(to: infoURL, atomically: true, encoding: .utf8)
            try workflow(command: command).write(to: docURL, atomically: true, encoding: .utf8)
            NSUpdateDynamicServices()   // make the menu pick it up without a relaunch
            AppInfo.logger("quickaction").info("Installed Quick Action → \(workflowURL.path, privacy: .public)")
        } catch {
            AppInfo.logger("quickaction").error("Couldn't install Quick Action: \(error.localizedDescription)")
        }
    }

    private static func infoPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>NSServices</key><array><dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Clean with \(Channel.current.displayName)</string></dict>
            <key>NSMessage</key><string>runWorkflowAsService</string>
            <key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
            <key>NSSendFileTypes</key><array><string>public.movie</string><string>public.audiovisual-content</string></array>
          </dict></array>
        </dict></plist>
        """
    }

    private static func workflow(command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>AMApplicationBuild</key><string>523</string>
          <key>AMApplicationVersion</key><string>2.10</string>
          <key>AMDocumentVersion</key><string>2</string>
          <key>actions</key><array><dict>
            <key>action</key><dict>
              <key>AMAccepts</key><dict><key>Container</key><string>List</string><key>Optional</key><true/><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
              <key>AMActionVersion</key><string>2.0.3</string>
              <key>AMApplication</key><array><string>Automator</string></array>
              <key>AMProvides</key><dict><key>Container</key><string>List</string><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
              <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
              <key>ActionName</key><string>Run Shell Script</string>
              <key>ActionParameters</key><dict>
                <key>COMMAND_STRING</key><string>\(escaped)</string>
                <key>CheckedForUserDefaultShell</key><true/>
                <key>inputMethod</key><integer>1</integer>
                <key>shell</key><string>/bin/zsh</string>
                <key>source</key><string></string>
              </dict>
              <key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
              <key>CFBundleVersion</key><string>2.0.3</string>
              <key>Class Name</key><string>RunShellScriptAction</string>
              <key>InputUUID</key><string>11111111-1111-1111-1111-111111111111</string>
              <key>OutputUUID</key><string>22222222-2222-2222-2222-222222222222</string>
              <key>UUID</key><string>33333333-3333-3333-3333-333333333333</string>
              <key>isViewVisible</key><integer>1</integer>
            </dict>
            <key>isViewVisible</key><integer>1</integer>
          </dict></array>
          <key>connectors</key><dict/>
          <key>workflowMetaData</key><dict>
            <key>serviceApplicationBundleID</key><string>com.apple.finder</string>
            <key>serviceApplicationPath</key><string>/System/Library/CoreServices/Finder.app</string>
            <key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
            <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
            <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
          </dict>
        </dict></plist>
        """
    }
}
