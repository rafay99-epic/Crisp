import SwiftUI

/// The app's own confirmation dialog — a styled sheet that matches Crisp's design
/// language (SF Symbol + headline + secondary explanation + a `.borderedProminent`
/// primary action), rather than a stock `.alert` that looks like a different app.
/// One shared component so every in-app confirmation reads the same (one system,
/// not two). Present it from a `Bool` binding via `.sheet(isPresented:)`.
struct ConfirmationSheet: View {
    let icon: String
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    /// Tints the primary button red for a destructive action (default: accent).
    var isDestructive: Bool = false
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Button(cancelTitle) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { onConfirm(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(isDestructive ? .red : .accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}
