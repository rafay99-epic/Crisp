import SwiftUI
import CrispCore

/// Shown when Ultra mode can't start because the Mac doesn't have enough free
/// memory (or is too hot) right now. There's no override — the user frees up
/// resources and taps Check Again until the preflight passes. Crisp never touches
/// the originals, so canceling here is always safe.
struct UltraPreflightSheet: View {
    let target: Int
    let verdict: ResourceGovernor.Verdict
    let onCheckAgain: () -> Void
    let onCancel: () -> Void

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useGB]
        return f
    }()

    private func gb(_ bytes: UInt64) -> String {
        Self.formatter.string(fromByteCount: Int64(bytes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: verdict.thermalBlocked ? "thermometer.high" : "memorychip")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not enough power right now").font(.headline)
                    Text(verdict.thermalBlocked
                         ? "Your Mac is running hot."
                         : "Ultra wants to clean \(target) videos at once.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if verdict.thermalBlocked {
                Text("Let your Mac cool down, then check again. Crisp won\u{2019}t start until it can do this safely \u{2014} your originals are never touched.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Needs", value: gb(verdict.neededBytes))
                    LabeledContent("Free now", value: gb(verdict.availableBytes))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(.quaternary.opacity(0.2), cornerRadius: 8)

                Text("Close some apps to free up memory, then check again. Crisp won\u{2019}t start until it fits \u{2014} your originals are never touched.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Check Again", action: onCheckAgain)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
