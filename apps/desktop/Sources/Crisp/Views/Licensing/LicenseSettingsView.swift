import SwiftUI
import CrispCore

/// The "License" section for the Settings ▸ General tab. Returns a `Section`, so it
/// drops straight into the grouped `Form` alongside the software-update section.
/// Only embedded when `Channel.licensingEnabled` is on (the caller guards), so it's
/// invisible while the feature ships dark.
struct LicenseSettingsView: View {
    @Bindable var license: LicenseStore
    @State private var keyField = ""
    @State private var confirmingDeactivate = false

    private var keyTrimmed: String { keyField.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Section {
            LabeledContent("Status") { statusBadge }
            if license.state == .licensed {
                activeRows
            } else {
                inactiveRows
            }
            if let message = license.message { messageRow(message) }
        } header: {
            Text("License")
        } footer: {
            Text("Crisp is \(PolarConfig.priceText). Your purchase supports development — the app stays open source (GPL-3.0).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Status badge

    @ViewBuilder private var statusBadge: some View {
        switch license.state {
        case .licensed:
            Label("Crisp Pro — Active", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .trial(let days):
            Label("Trial — \(days) day\(days == 1 ? "" : "s") left", systemImage: "clock")
                .foregroundStyle(days <= 3 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        case .trialExpired:
            Label("Trial ended", systemImage: "lock.fill").foregroundStyle(.orange)
        case .revoked:
            Label("Inactive", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .checking:
            Label("Checking…", systemImage: "ellipsis").foregroundStyle(.secondary)
        case .unlicensed:
            Label("Not licensed", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    // MARK: - Licensed

    @ViewBuilder private var activeRows: some View {
        if let masked = license.maskedKey {
            LabeledContent("Key") {
                HStack(spacing: 6) {
                    Text(masked).monospaced()
                    Button(action: copyKey) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy license key")
                }
            }
        }
        HStack {
            Button("Manage Subscription") { license.openPortal() }
            Spacer()
            Button("Deactivate This Mac", role: .destructive) { confirmingDeactivate = true }
                .disabled(license.isWorking)
        }
        .confirmationDialog("Deactivate Crisp on this Mac?",
                            isPresented: $confirmingDeactivate, titleVisibility: .visible) {
            Button("Deactivate", role: .destructive) { Task { await license.deactivate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees the device so you can use your license on another Mac. You can re-enter your key here any time.")
        }
    }

    // MARK: - Unlicensed / trial / expired

    @ViewBuilder private var inactiveRows: some View {
        // The primary CTA for someone who's never started: a free trial.
        if case .unlicensed = license.state {
            Button { license.startTrial() } label: {
                Label("Start \(PolarConfig.trialDays)-Day Free Trial", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(license.isWorking)
        }

        // License-key entry on its own full-width row (no longer cramped in a label's
        // trailing edge). Field expands; Activate is the prominent action beside it.
        VStack(alignment: .leading, spacing: 6) {
            Text("Have a license key?").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                // `prompt:` renders the hint INSIDE the field; `.labelsHidden()` drops the
                // leading label macOS would otherwise show beside it.
                TextField("License key", text: $keyField, prompt: Text("CRISP-XXXX-XXXX-XXXX"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(activate)
                    .disabled(license.isWorking)
                Button(action: activate) {
                    if license.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.isWorking || keyTrimmed.isEmpty)
            }
        }

        HStack {
            Button("Subscribe (\(PolarConfig.priceText))") { license.openCheckout() }
                .disabled(license.isWorking)
            Spacer()
            // The portal is also where buyers free up a device when they hit the limit.
            Button("Manage devices / lost key") { license.openPortal() }
                .buttonStyle(.link)
        }
    }

    // MARK: - Inline feedback

    @ViewBuilder private func messageRow(_ message: String) -> some View {
        let ok = license.state.canClean   // success path lands on licensed/trial
        Label(message, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func copyKey() {
        NSPasteboard.general.clearContents()
        if let key = LicenseStorage.licenseKey {
            NSPasteboard.general.setString(key, forType: .string)
        }
    }

    private func activate() {
        let key = keyField
        Task { await license.activate(key: key) }
    }
}
