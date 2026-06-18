import SwiftUI

/// The empty-state hero: a big, inviting drop zone shown when the queue is empty.
/// Once files are added the queue list takes over and files are added from the
/// toolbar's + button (or by dropping anywhere on the window).
struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No videos added").font(.headline)
            Text("Drag videos here, or").font(.callout).foregroundStyle(.secondary)
            Button("Choose videos\u{2026}") { importing = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
