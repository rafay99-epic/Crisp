import SwiftUI

/// The "Reveal Backed-up Original" + "Restore Original…" context-menu actions, shared
/// by the queue done-row and the History row so the two never drift ("one system, not
/// two"). Drop into any `.contextMenu { … }` when a backup exists.
struct BackupMenuItems: View {
    let backupPath: String
    /// The source's path, used to default the restore destination beside it.
    let sourcePath: String

    var body: some View {
        Button { Restore.revealBackup(backupPath) } label: {
            Label("Reveal Backed-up Original", systemImage: "clock.arrow.circlepath")
        }
        Button { Restore.restoreOriginal(backupPath: backupPath, sourcePath: sourcePath) } label: {
            Label("Restore Original\u{2026}", systemImage: "arrow.uturn.backward")
        }
    }
}
