import SwiftUI
import AppKit
import CrispCore

/// The "What's New" sheet shown once after an update — the app icon, a title, and the
/// release's highlights. Prefers the running version's GitHub release notes (parsed
/// into clean sections); falls back to a curated list when notes aren't available
/// (offline / dev build). Native look, matching the onboarding tour.
struct WhatsNewView: View {
    @Bindable var whatsNew: WhatsNewController
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

            ScrollView {
                if whatsNew.highlights.isEmpty {
                    fallback
                } else {
                    notes
                }
            }
            .frame(maxHeight: 320)

            Button("Continue") { onDismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }

    /// Release-notes path: a clean, flat list of user-facing highlight titles.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(whatsNew.highlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle").font(.callout).foregroundStyle(.tint)
                        .padding(.top, 2)
                    Text(highlight).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Fallback path: curated highlights when notes can't be fetched.
    private var fallback: some View {
        VStack(spacing: 12) {
            ForEach(WhatsNewController.fallback) { item in
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
    }
}
