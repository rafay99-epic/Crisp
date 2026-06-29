import Foundation

/// Polar.sh product configuration for the paid tier ("Crisp Pro", $8/mo). Centralised
/// so there's a single place to manage the account-specific identifiers.
///
/// These are **not secrets** — the organization id and the hosted checkout/portal URLs
/// are public-facing (they'd be visible in any client), so it's fine for them to live
/// in source, exactly as the validate/activate endpoints are public customer-portal
/// APIs needing no token. The licensing system still ships **dark**
/// (`Channel.licensingEnabled == false`, see `Channel`): none of these are hit until
/// the flag is flipped on.
public enum PolarConfig {
    /// Polar organization id (UUID), used to scope license-key validate/activate calls.
    public static let organizationID = "ae6a2275-d1b4-4449-8760-29d6d19e2e68"

    /// Hosted checkout for the Crisp Pro $8/mo subscription.
    public static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_3wnFYuNlirHXRyOOLU01B7pWXKj8xs2zuplXM0OgvJO")!

    /// Polar's built-in customer portal (org slug `crisp`): buyers manage their
    /// subscription, copy their license key, and deactivate devices there.
    public static let portalURL = URL(string: "https://polar.sh/crisp/portal")!

    /// Shown in paywall copy. No annual / lifetime tier for now.
    public static let priceText = "$8/mo"

    /// Free-trial length, in days.
    public static let trialDays = 14
}
