import SwiftUI

struct ProgressSection: View {
    @Bindable var model: CleanModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: model.progress)
                .tint(model.errorMessage == nil ? .accentColor : .red)
            HStack {
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.logLines.isEmpty {
                Button {
                    withAnimation(.snappy) { showLog.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(showLog ? 90 : 0))
                        Text("Details")
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())   // make the whole row clickable
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if showLog {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(model.logLines.enumerated()), id: \.offset) { i, line in
                                    Text(line).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 110)
                        .cardBackground(.quaternary.opacity(0.2), cornerRadius: 8)
                        .onChange(of: model.logLines.count) { _, c in
                            withAnimation { proxy.scrollTo(c - 1, anchor: .bottom) }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
