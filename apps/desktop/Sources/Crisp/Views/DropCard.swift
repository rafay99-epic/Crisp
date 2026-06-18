import SwiftUI

struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.queue.isEmpty ? "film.stack" : "plus.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.queue.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text("Drag videos here, or").font(.callout).foregroundStyle(.secondary)
            Button(model.queue.isEmpty ? "Choose videos\u{2026}" : "Add more\u{2026}") { importing = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
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
        .disabled(model.isRunning)
    }

    private var title: String {
        if model.queue.isEmpty { return "No videos added" }
        let count = model.queue.count
        return count == 1 ? "1 video in the queue" : "\(count) videos in the queue"
    }
}
