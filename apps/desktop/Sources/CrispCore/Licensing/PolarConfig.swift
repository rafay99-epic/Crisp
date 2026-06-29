import Foundation

/// Polar.sh product configuration for the paid tier. Centralised so there's a single
/// place to fill in once the Polar account is set up.
///
/// > **Placeholders, on purpose.** The `organizationID` and URLs below are stubs.
/// > The whole licensing system ships **dark** (`Channel.licensingEnabled == false`,
/// > see `Channel`), so none of these are ever hit until the flag is flipped on —
/// > by which point the real values must be filled in. No network call references
/// > them while the feature is off.
public enum PolarConfig {
    /// Polar organization id (UUID from the Polar dashboard). **TODO(licensing):
    /// replace before enabling the feature flag.**
    public static let organizationID = "REPLACE_WITH_POLAR_ORGANIZATION_ID"

    /// Hosted checkout for the $8/mo subscription. **TODO(licensing): replace.**
    public static let checkoutURL = URL(string: "https://polar.sh")!

    /// Customer portal where a buyer manages / deactivates devices and recovers a
    /// lost key. **TODO(licensing): replace.**
    public static let portalURL = URL(string: "https://polar.sh")!

    /// Shown in paywall copy. No annual / lifetime tier for now.
    public static let priceText = "$8/mo"

    /// Free-trial length, in days.
    public static let trialDays = 14
}
