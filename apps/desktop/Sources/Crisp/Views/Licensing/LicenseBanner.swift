import SwiftUI
import CrispCore

/// The paywall surface shown above the queue when licensing is active. One card
/// across the states that warrant attention — unlicensed, trial ending, trial
/// expired, revoked — mirroring `ModelStatusView`'s shape. Returns nothing (so the
/// workspace is unchanged) when licensed, early in a trial, or — crucially — whenever
/// the feature flag is off, so the app looks exactly like today while shipped dark.
struct LicenseBanner: View {
    @Bindable var license: LicenseStore

    var body: some View {
        if let info {
            HStack(spacing: 12) {
                Image(systemName: info.icon).font(.title2).foregroundStyle(info.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(.headline)
                    Text(info.subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                actions
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .padding(.horizontal, 16).padding(.top, 10)
        }
    }

    private struct Info {
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    /// What to show — or `nil` to show nothing (feature off, licensed, or a trial with
    /// plenty of time left).
    private var info: Info? {
        guard Channel.licensingEnabled else { return nil }
        switch license.state {
        case .checking, .licensed:
            return nil
        case .trial(let daysLeft):
            guard daysLeft <= 3 else { return nil }   // only nag near the end
            return Info(icon: "clock.badge.exclamationmark", tint: .orange,
                        title: "\(daysLeft) day\(daysLeft == 1 ? "" : "s") left in your trial",
                        subtitle: "Subscribe (\(PolarConfig.priceText)) to keep cleaning after your trial ends.")
        case .trialExpired:
            return Info(icon: "lock.fill", tint: .orange,
                        title: "Your trial has ended",
                        subtitle: "Subscribe (\(PolarConfig.priceText)) or enter a license key to keep cleaning videos.")
        case .unlicensed:
            return Info(icon: "sparkles", tint: .accentColor,
                        title: "Start your free \(PolarConfig.trialDays)-day trial",
                        subtitle: "Try Crisp free for \(PolarConfig.trialDays) days — no card needed. Subscribe any time (\(PolarConfig.priceText)).")
        case .revoked:
            return Info(icon: "exclamationmark.triangle.fill", tint: .orange,
                        title: "Your license is no longer active",
                        subtitle: "Renew your subscription or enter a valid license key to keep cleaning.")
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if case .unlicensed = license.state {
                Button("Start Free Trial") { license.startTrial() }
                    .buttonStyle(.borderedProminent)
                Button("Subscribe") { license.openCheckout() }
                // Returning paid users land here too — give them a direct key path.
                SettingsLink { Text("Enter Key") }
            } else {
                Button("Subscribe") { license.openCheckout() }
                    .buttonStyle(.borderedProminent)
                SettingsLink { Text("Enter Key") }
            }
        }
        .controlSize(.large)
        .disabled(license.isWorking)
    }
}
