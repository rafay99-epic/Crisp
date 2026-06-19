import SwiftUI
import AppKit
import CrispCore

/// The "What's New" sheet shown once after an update — the app icon, a title, and the
/// release's highlights. Native: SF Symbols on tinted marks, a `.borderedProminent`
/// dismiss, matching the onboarding tour's look.
struct WhatsNewView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("What’s New in \(Channel.current.displayName)")
                    .font(.title2.bold()).multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ForEach(WhatsNewController.items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.title3).foregroundStyle(.tint).frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button("Continue") { onDismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }
}
