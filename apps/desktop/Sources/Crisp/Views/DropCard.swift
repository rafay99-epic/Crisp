import SwiftUI

/// The empty-state hero: a big, inviting drop zone shown when the queue is empty.
/// Once files are added the queue list takes over and files are added from the
/// toolbar's + button (or by dropping anywhere on the window).
struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            // The app's own mark — a waveform — gently animating, so the empty
            // state says "audio tool" at a glance instead of a generic file box.
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.75)))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                .padding(.bottom, 2)
            Text(targeted ? "Drop to add" : "No videos added").font(.headline)
            Text("Drag videos here, or").font(.callout).foregroundStyle(.secondary)
            Button("Choose videos\u{2026}") { importing = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .animation(.smooth, value: targeted)
        .cardBackground(.quaternary.opacity(targeted ? 0.6 : 0.25))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls)
            return true
        } isTargeted: { targeted = $0 }
    }
}
