import SwiftUI
import CrispCore

/// The "your cuts are ready" picker — a custom, on-brand sheet (not a system dialog)
/// that lists the video editors found on the Mac, each with its own Open button. Shown
/// after an editor-handoff cut finishes. The free tier can't auto-import, so opening an
/// editor is all we do; the sheet says the one manual step plainly.
struct EditorPickerSheet: View {
    let editors: [VideoEditor]
    let onOpen: (VideoEditor) -> Void
    let onReveal: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .padding(20)
            footer
        }
        .frame(width: 440)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("Your cuts are ready")
                .font(.title2.weight(.semibold))
            Text(editors.isEmpty
                 ? "Crisp saved your cuts as an editable timeline."
                 : "Crisp opens your editor and reveals the timeline file in Finder — your footage is never touched.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        if editors.isEmpty {
            // No editor installed: guide the user, offer Finder as the fallback.
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No video editor found")
                    .font(.headline)
                Text("Install DaVinci Resolve — the free version works great — then open the timeline from the project folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .cardBackground()
        } else {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    ForEach(editors) { editor in
                        editorRow(editor)
                    }
                }
                importSteps
            }
        }
    }

    /// The two manual steps after opening — kept explicit so the handoff never feels
    /// half-finished. (Free editors can't auto-import; this is the whole job, plainly.)
    private var importSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("In your editor, choose **File ▸ Import ▸ Timeline**", systemImage: "1.circle.fill")
            Label("Pick the **.fcpxml** Crisp just revealed in Finder", systemImage: "2.circle.fill")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }

    private func editorRow(_ editor: VideoEditor) -> some View {
        HStack(spacing: 13) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: editor.appURL.path))
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.name)
                    .font(.headline)
                Text("Found on your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                onOpen(editor)
                dismiss()
            } label: {
                Text("Open").frame(minWidth: 54)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .cardBackground()
    }

    private var footer: some View {
        HStack {
            Button {
                onReveal()
                dismiss()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.link)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.12))
    }
}
