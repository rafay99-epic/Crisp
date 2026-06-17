import SwiftUI

struct ResultCard: View {
    @Bindable var model: CleanModel

    private var totalSaved: Double { model.results.reduce(0) { $0 + $1.savedSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.results.count == 1 ? "Cleaned!" : "Cleaned \(model.results.count) videos")
                        .font(.headline)
                    Text("Removed \(formatTime(totalSaved)) of pauses & fillers.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let first = model.results.first, model.results.count == 1 {
                HStack(spacing: 16) {
                    stat("\(formatTime(first.origSeconds)) \u{2192} \(formatTime(first.newSeconds))", "Length")
                    stat("\(first.pauses)", "Pauses cut")
                    stat("\(first.fillers)", "Fillers cut")
                }
            }
            HStack {
                Button {
                    if let path = model.results.last?.output {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } label: { Label("Show in Finder", systemImage: "folder") }
                .controlSize(.large)

                Button { model.reset() } label: {
                    Label("Clean another", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.green.opacity(0.12))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
