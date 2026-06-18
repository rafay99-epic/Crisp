import SwiftUI

struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        // Empty queue → a big, inviting drop zone (the primary call to action).
        // Once files are queued, collapse to a slim "add more" bar so the queue and
        // controls stay on screen.
        Group {
            if model.queue.isEmpty { emptyZone } else { compactBar }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls)
            return true
        } isTargeted: { targeted = $0 }
        .disabled(model.isRunning)
    }

    private var emptyZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No videos added").font(.headline).multilineTextAlignment(.center)
            Text("Drag videos here, or").font(.callout).foregroundStyle(.secondary)
            Button("Choose videos\u{2026}") { importing = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardBackground(.quaternary.opacity(targeted ? 0.6 : 0.25))
        .overlay(dashedBorder)
    }

    private var compactBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text("Add more videos").font(.callout)
            Spacer(minLength: 8)
            Text("or drag here").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { importing = true }
        .cardBackground(.quaternary.opacity(targeted ? 0.6 : 0.25))
        .overlay(dashedBorder)
    }

    private var dashedBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
    }
}
