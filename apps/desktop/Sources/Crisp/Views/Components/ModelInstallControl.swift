import SwiftUI
import CrispCore

/// The install / progress / ready lifecycle for the model a `ModelStore` currently
/// tracks — one rendering shared by the onboarding model step and the Settings
/// speech-model section, so the six states (install / downloading / verifying /
/// failed / ready) live in a single place. The caller supplies the surrounding
/// chrome; this is the inner row. (The workspace gate uses the larger
/// `ModelStatusView` banner, which carries its own headline + repair copy.)
struct ModelInstallControl: View {
    @Bindable var store: ModelStore
    /// Offer a Remove button when the model is installed (Settings only).
    var allowRemove = false
    /// Disable Remove — e.g. while a clean is running.
    var removeDisabled = false

    var body: some View {
        HStack(spacing: 10) {
            switch store.state {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(store.spec.displayName) installed \u{00B7} \(store.spec.approxSizeText)")
                    .font(.callout)
                Spacer(minLength: 8)
                if allowRemove {
                    Button("Remove", role: .destructive) { Task { await store.deleteSelected() } }
                        .controlSize(.small)
                        .disabled(removeDisabled)
                }
            case .downloading(let fraction):
                ProgressView(value: fraction < 0 ? nil : fraction).frame(width: 130)
                Text(fraction < 0 ? "Downloading\u{2026}" : "Downloading\u{2026} \(Int(fraction * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel") { store.cancel() }.controlSize(.small)
            case .verifying:
                ProgressView().controlSize(.small)
                Text("Verifying\u{2026}").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Try Again") { store.download() }.controlSize(.small)
            default:   // absent / checking
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("Install \(store.spec.displayName) \u{00B7} \(store.spec.approxSizeText)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Install") { store.download() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}
