import Foundation
import Security

/// Minimal Keychain wrapper — the app's first use of the system Keychain, added for
/// the licensing layer. Values are stored as generic-password items under a
/// **per-channel** service, so Stable / Nightly / Dev never read each other's
/// license (mirrors how `Channel.dataDirectory` keeps channels isolated).
///
/// Dev builds (often ad-hoc-signed by `./dev.sh`) can't always persist Keychain
/// items reliably, so **Dev transparently falls back to `UserDefaults`** — safe
/// because the Dev channel is local-only and never sold. Stable/Nightly always use
/// the real Keychain.
public enum Keychain {
    private static var service: String {
        AppInfo.bundleIdentifier + Channel.current.bundleSuffix + ".license"
    }

    /// Dev sidesteps the Keychain (see type doc).
    private static var usesFallback: Bool { Channel.current == .dev }
    private static func fallbackKey(_ account: String) -> String { "LicenseKeychain.\(account)" }

    public static func string(for account: String) -> String? {
        if usesFallback { return UserDefaults.standard.string(forKey: fallbackKey(account)) }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Set (or, with `nil`, remove) the value for `account`.
    public static func set(_ value: String?, for account: String) {
        guard let value else { remove(account); return }
        if usesFallback {
            UserDefaults.standard.set(value, forKey: fallbackKey(account))
            return
        }
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public static func remove(_ account: String) {
        if usesFallback {
            UserDefaults.standard.removeObject(forKey: fallbackKey(account))
            return
        }
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Device-local; never synced to iCloud Keychain (a license is per-Mac).
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
