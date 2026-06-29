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

    var body: some View {
        Section {
            switch license.state {
            case .licensed:
                activeRows
            default:
                inactiveRows
            }
            if let message = license.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("License")
        } footer: {
            Text("Crisp is \(PolarConfig.priceText). Your purchase supports development — the app stays open source (GPL-3.0).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Licensed

    @ViewBuilder private var activeRows: some View {
        LabeledContent("Status") {
            Label("Active", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        }
        if let masked = license.maskedKey {
            LabeledContent("Key") {
                HStack(spacing: 6) {
                    Text(masked).monospaced()
                    Button {
                        NSPasteboard.general.clearContents()
                        if let key = LicenseStorage.licenseKey {
                            NSPasteboard.general.setString(key, forType: .string)
                        }
                    } label: { Image(systemName: "doc.on.doc") }
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
        LabeledContent("Status") { Text(statusText) }

        if case .unlicensed = license.state {
            Button("Start Free \(PolarConfig.trialDays)-Day Trial") { license.startTrial() }
        }

        LabeledContent("License key") {
            HStack(spacing: 8) {
                TextField("XXXX-XXXX-XXXX", text: $keyField)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .onSubmit { activate() }
                    .disabled(license.isWorking)
                if license.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button(license.isWorking ? "Activating…" : "Activate", action: activate)
                    .disabled(license.isWorking || keyField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }

        HStack {
            Button("Subscribe (\(PolarConfig.priceText))") { license.openCheckout() }
                .disabled(license.isWorking)
            Spacer()
            // The portal is also where buyers free up a device when they hit the limit.
            Button("Manage devices / lost key") { license.openPortal() }.buttonStyle(.link)
        }
    }

    private var statusText: String {
        switch license.state {
        case .trial(let d):  return "Trial — \(d) day\(d == 1 ? "" : "s") left"
        case .trialExpired:  return "Trial ended"
        case .revoked:       return "License inactive"
        case .checking:      return "Checking…"
        default:             return "Not licensed"
        }
    }

    private func activate() {
        let key = keyField
        Task { await license.activate(key: key) }
    }
}
