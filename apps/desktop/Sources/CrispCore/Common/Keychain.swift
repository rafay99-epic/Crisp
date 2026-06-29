import Foundation
import Security

/// Minimal Keychain wrapper — the app's first use of the system Keychain, added for
/// the licensing layer. Values are stored as generic-password items under a
/// **per-channel** service, so Stable / Nightly / Dev never read each other's
/// license (mirrors how `Channel.dataDirectory` keeps channels isolated).
///
/// Dev builds (ad-hoc-signed by `./dev.sh`) can re-sign on every rebuild, which can
/// break Keychain item access, so **non-secret** Dev state may fall back to
/// `UserDefaults` for dogfooding convenience. **Secrets never do** — callers pass
/// `allowDevFallback: false` for the license key and activation id so credential
/// material is never written to plaintext preferences, even on Dev.
public enum Keychain {
    private static let log = AppInfo.logger("keychain")

    private static var service: String {
        AppInfo.bundleIdentifier + Channel.current.bundleSuffix + ".license"
    }

    private static var isDev: Bool { Channel.current == .dev }
    private static func fallbackKey(_ account: String) -> String { "LicenseKeychain.\(account)" }

    public static func string(for account: String, allowDevFallback: Bool = true) -> String? {
        if isDev && allowDevFallback { return UserDefaults.standard.string(forKey: fallbackKey(account)) }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain read failed for \(account, privacy: .public): OSStatus \(status)")
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Set (or, with `nil`, remove) the value for `account`. Returns whether the write
    /// succeeded, so callers (e.g. activation) can surface a failure instead of leaving
    /// licensing state silently stale.
    @discardableResult
    public static func set(_ value: String?, for account: String, allowDevFallback: Bool = true) -> Bool {
        guard let value else { return remove(account, allowDevFallback: allowDevFallback) }
        if isDev && allowDevFallback {
            UserDefaults.standard.set(value, forKey: fallbackKey(account))
            return true
        }
        let data = Data(value.utf8)
        let query = baseQuery(account)
        var status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            log.error("Keychain write failed for \(account, privacy: .public): OSStatus \(status)")
            return false
        }
        return true
    }

    @discardableResult
    public static func remove(_ account: String, allowDevFallback: Bool = true) -> Bool {
        if isDev && allowDevFallback {
            UserDefaults.standard.removeObject(forKey: fallbackKey(account))
            return true
        }
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain delete failed for \(account, privacy: .public): OSStatus \(status)")
            return false
        }
        return true
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        // The default (file-based) keychain — NOT the data-protection keychain, which
        // requires a keychain-access-group entitlement Crisp doesn't ship; without it
        // saves fail with errSecMissingEntitlement and the gate would wrongly treat a
        // paying user as unlicensed. Items aren't synced to iCloud (no
        // kSecAttrSynchronizable), so a license stays per-Mac.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
