import Foundation

/// Polar.sh product configuration for the paid tier ("Crisp Pro", $8/mo).
///
/// The account-specific identifiers (org id + checkout/portal/lookup URLs) are **not
/// hardcoded** — they're injected at build time into the app's Info.plist by
/// `build.sh` from `CRISP_POLAR_*` environment variables, so the values live in your
/// build secrets (a gitignored `apps/desktop/.polar.env` for dev, GitHub Actions
/// secrets for release) and never in the committed source. When a key is absent the
/// accessor returns `nil`/`""`, which is fine while the feature ships dark
/// (`Channel.licensingEnabled == false`) — nothing reads them until the flag is on.
///
/// (These aren't secrets — the Polar API token lives only in the serverless function —
/// but keeping them out of the public repo is cleaner and avoids casual probing.)
public enum PolarConfig {
    /// Polar organization id (UUID), used to scope license-key validate/activate calls.
    /// `nil` when not injected — consistent with the URL accessors, so a missing config
    /// surfaces as "not configured" (PolarService throws) rather than a silent empty id.
    public static var organizationID: String? { string("CrispPolarOrgID") }

    /// Hosted checkout for the Crisp Pro $8/mo subscription.
    public static var checkoutURL: URL? { url("CrispPolarCheckoutURL") }

    /// Polar's built-in customer portal: buyers manage their subscription, copy their
    /// license key, and deactivate devices there.
    public static var portalURL: URL? { url("CrispPolarPortalURL") }

    /// Serverless endpoint that maps a Polar `checkout_id` → license key, so the app can
    /// finish a purchase automatically after the `crisp://activate` deep link. The Polar
    /// API token lives in that function (server-side), never in this client. `nil` ⇒
    /// auto-activation is disabled and the user falls back to pasting the key.
    /// See `apps/license-api/` for the deployed function.
    public static var licenseLookupURL: URL? { url("CrispPolarLookupURL") }

    /// Shown in paywall copy. Non-sensitive product config — fine to keep in source.
    public static let priceText = "$8/mo"

    /// Free-trial length, in days.
    public static let trialDays = 14

    // MARK: - Info.plist accessors

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func url(_ key: String) -> URL? { string(key).flatMap(URL.init(string:)) }
}
