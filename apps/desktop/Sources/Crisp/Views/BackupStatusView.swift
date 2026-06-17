import SwiftUI
import AppKit

/// A slim row that tells the user — at a glance, before they hit Clean — what
/// happens to their original: where the safety copy is kept, or that backups are
/// off. The source file is never edited either way (only a cleaned copy is
/// written); this row is purely about that extra backup.
struct BackupStatusView: View {
    /// Whether the "keep a backup" setting is on.
    let backupOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: backupOn ? "checkmark.shield.fill" : "shield.slash.fill")
                .font(.title3)
                .foregroundStyle(backupOn ? Color.accentColor : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(backupOn ? "Originals are backed up" : "Backups are off")
                    .font(.subheadline.weight(.medium))
                Text(backupOn
                     ? friendlyPath
                     : "Originals won\u{2019}t be copied \u{2014} but your source files are never changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if backupOn {
                Button("Show in Finder") { reveal() }
                    .buttonStyle(.link)
                    .controlSize(.small)
            } else {
                SettingsLink { Text("Turn on\u{2026}") }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(backupOn ? AnyShapeStyle(.quaternary.opacity(0.25))
                                 : AnyShapeStyle(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// `~`-abbreviated parent folder, e.g. `~/.crisp/Originals`.
    private var friendlyPath: String {
        (CleanModel.backupParentDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    /// Open the Originals folder in Finder, creating it first so the reveal works
    /// even before the first clean has written anything into it.
    private func reveal() {
        let dir = CleanModel.backupParentDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
