import SwiftUI

/// First-run / resume / repair surface for the whisper speech model. One shared
/// card across every state — missing, downloading, verifying, failed — so the
/// download experience lives in exactly one place.
struct ModelStatusView: View {
    @Bindable var store: ModelStore

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .downloading(let p) = store.state, p >= 0 {
                    ProgressView(value: p).padding(.top, 4)
                }
            }
            Spacer()
            trailing
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder private var icon: some View {
        switch store.state {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(.orange)
        case .downloading, .verifying, .checking:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.title2).foregroundStyle(.tint)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch store.state {
        case .absent:
            Button("Download") { store.download() }.controlSize(.large)
        case .downloading:
            Button("Cancel") { store.cancel() }.controlSize(.small)
        case .failed:
            Button("Try Again") { store.download() }.controlSize(.large)
        default:
            EmptyView()
        }
    }

    private var title: String {
        switch store.state {
        case .checking:    return "Checking speech model\u{2026}"
        case .ready:       return "Speech model ready"
        case .absent:      return "Speech model needed"
        case .downloading: return "Downloading speech model\u{2026}"
        case .verifying:   return "Verifying speech model\u{2026}"
        case .failed:      return "Couldn\u{2019}t download speech model"
        }
    }

    private var subtitle: String {
        switch store.state {
        case .downloading(let p) where p >= 0:
            return "\(Int(p * 100))% \u{2014} keep Crisp open until it finishes."
        case .downloading:
            return "Keep Crisp open until it finishes."
        case .failed(let msg):
            return msg
        default:
            return "A one-time \(store.spec.approxSizeText) download lets Crisp find filler words. "
                 + "Turn off \u{201C}Remove fillers\u{201D} to skip it."
        }
    }
}
