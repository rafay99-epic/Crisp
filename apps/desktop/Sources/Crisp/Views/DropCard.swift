import SwiftUI

struct DropCard: View {
    @Bindable var model: CleanModel
    @Binding var importing: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.files.isEmpty ? "film.stack" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.files.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text("Drag a video here, or").font(.callout).foregroundStyle(.secondary)
            Button("Choose video\u{2026}") { importing = true }
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
        if model.files.isEmpty { return "No video selected" }
        if model.files.count == 1 { return model.files[0].lastPathComponent }
        return "\(model.files.count) videos selected"
    }
}
