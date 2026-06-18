import SwiftUI
import AppKit
import CrispCore

/// First-run welcome flow: a short, paged tour of what Crisp does and every way to
/// use it. Native, Apple-like — system materials, SF Symbols, a `.borderedProminent`
/// primary action, and page dots. Re-openable from Help ▸ Welcome to Crisp.
struct OnboardingView: View {
    @Bindable var onboarding: OnboardingController
    @Bindable var modelStore: ModelStore
    @State private var page = 0

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private struct Page: Identifiable {
        let id: Int
        let symbol: String          // header SF Symbol; empty ⇒ use the app icon
        let title: String
        let subtitle: String
        var features: [Feature] = []
        var showsModel = false      // the filler page shows the model-download widget
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "",
             title: "Welcome to Crisp",
             subtitle: "Crisp tightens up your screen recordings and talking-head videos — automatically cutting out long pauses and filler words to leave clean, snappy jump-cuts.",
             features: [
                Feature(symbol: "checkmark.shield.fill", title: "Your footage is safe",
                        detail: "Crisp never edits or deletes your original. It only ever writes a new cleaned copy beside it."),
                Feature(symbol: "rectangle.on.rectangle", title: "No quality loss",
                        detail: "Cuts re-encode at the same resolution and frame rate — never downscaled.")
             ]),
        Page(id: 1, symbol: "wand.and.stars",
             title: "Clean a video in seconds",
             subtitle: "Three steps, and you’re done.",
             features: [
                Feature(symbol: "film.stack", title: "Drop or choose a video",
                        detail: "Drag a recording onto the window, or click “Choose video…”."),
                Feature(symbol: "slider.horizontal.3", title: "Pick how much to cut",
                        detail: "Gentle through Very Aggressive — or Custom for full control."),
                Feature(symbol: "scissors", title: "Hit Clean",
                        detail: "Crisp finds the silences and fillers and cuts them out, saving “name_cleaned.mp4”.")
             ]),
        Page(id: 2, symbol: "waveform",
             title: "Pauses & filler words",
             subtitle: "Crisp removes dead air, and can also strip the “um”s and “uh”s.",
             features: [
                Feature(symbol: "waveform", title: "Pauses — always on",
                        detail: "Detected from the real audio. Works out of the box, no setup."),
                Feature(symbol: "text.bubble.fill", title: "Filler words — optional",
                        detail: "Turn on “Remove filler words” and Crisp downloads a one-time speech model. Pauses-only needs no download.")
             ],
             showsModel: true),
        Page(id: 3, symbol: "bolt.fill",
             title: "Make it automatic",
             subtitle: "Crisp fits into the way you already work.",
             features: [
                Feature(symbol: "cursorarrow.click.2", title: "Finder right-click",
                        detail: "Right-click any video → Services → Clean with Crisp."),
                Feature(symbol: "square.stack.3d.up.fill", title: "Shortcuts",
                        detail: "Add the “Clean with Crisp” action to any Shortcut or automation."),
                Feature(symbol: "folder.badge.gearshape", title: "Watch Folder",
                        detail: "Pick a folder and Crisp auto-cleans anything dropped in — even when it’s closed.")
             ]),
        Page(id: 4, symbol: "checkmark.seal.fill",
             title: "You’re all set",
             subtitle: "Fine-tune everything in Settings (⌘,): cutting strength, video & audio encoder, output format, backups, and the watch folder. You can reopen this guide any time from the Help menu.",
             features: [])
    ]

    private var current: Page { pages[page] }
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if !current.features.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(current.features) { featureRow($0) }
                        }
                        .padding(.top, 4)
                    }
                    if current.showsModel { modelWidget }
                }
                .padding(.horizontal, 44)
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .id(page)                      // re-trigger the transition per page
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        VStack(spacing: 14) {
            if current.symbol.isEmpty {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 84, height: 84)
            } else {
                Image(systemName: current.symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 84, height: 84)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            }
            Text(current.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(current.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }

    // MARK: - Optional model download (filler page)

    @ViewBuilder private var modelWidget: some View {
        HStack(spacing: 10) {
            switch modelStore.state {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Speech model ready — filler removal is set up.").font(.callout)
            case .downloading(let fraction):
                ProgressView(value: fraction < 0 ? nil : fraction).frame(width: 130)
                Text(fraction < 0 ? "Downloading…" : "Downloading… \(Int(fraction * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
            case .verifying:
                ProgressView().controlSize(.small)
                Text("Verifying…").font(.callout).foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.callout).foregroundStyle(.secondary)
            default:
                Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                Text("Set up filler removal now (optional):").font(.callout).foregroundStyle(.secondary)
                Button("Download (~148 MB)") { modelStore.download() }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(.tint.opacity(0.08))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation(.snappy) { page -= 1 } }
                    .buttonStyle(.link)
            } else {
                Button("Skip") { onboarding.finish() }
                    .buttonStyle(.link)
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()

            Button(isLast ? "Get Started" : "Continue") {
                if isLast { onboarding.finish() } else { withAnimation(.snappy) { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
