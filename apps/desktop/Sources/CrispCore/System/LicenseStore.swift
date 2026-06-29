import Foundation
import OSLog
import Security

/// Manages the licensing lifecycle and offline-tolerant validation.
/// Mirrors ModelStore: trial -> key/OAuth gate, state derived on launch, offline-tolerant.
@MainActor
@Observable
public final class LicenseStore {
    public enum State: Equatable {
        case checking
        case trial(daysLeft: Int)
        case active
        case offlineGrace(daysLeft: Int)
        case expired(String)
        case invalid(String)
        
        public var isUsable: Bool {
            switch self {
            case .trial, .active, .offlineGrace: return true
            case .checking, .expired, .invalid: return false
            }
        }
    }
    
    public private(set) var state: State = .checking
    
    private let defaults = UserDefaults.standard
    private static let log = Logger(subsystem: "com.crisp.app", category: "LicenseStore")
    
    // Config
    private let trialDays = 14
    private let offlineGraceDays = 14
    
    // Keys
    private let firstLaunchDateKey = "LicenseStore_FirstLaunchDate"
    private let lastValidationDateKey = "LicenseStore_LastValidationDate"
    private let lastSeenDateKey = "LicenseStore_LastSeenDate" // Anti clock-rollback
    
    // Keychain service identifier
    private let keychainService = "com.crisp.app.license"
    private let keychainAccount = "polar_license_key"
    
    private var isRefreshing = false
    
    public init() {}
    
    /// Called on app launch to determine the current state.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        state = .checking
        updateLastSeenDate()
        
        // 1. Check if a license key exists in Keychain
        guard let key = loadKeyFromKeychain() else {
            // No license key, evaluate trial
            state = evaluateTrialState()
            return
        }
        
        // 2. Validate existing key
        do {
            let response = try await PolarAPIClient.shared.validate(key: key)
            if response.isActive {
                defaults.set(Date(), forKey: lastValidationDateKey)
                state = .active
            } else {
                state = .expired("Your license key is no longer active.")
            }
        } catch let error as PolarAPIError {
            // 3. Network or Server error -> Fallback to Offline Grace
            if case .networkError(_) = error {
                state = evaluateOfflineGrace()
            } else if case .validationFailed(let msg) = error {
                state = .invalid("Validation failed: \(msg)")
            } else {
                state = evaluateOfflineGrace()
            }
        } catch {
            state = evaluateOfflineGrace()
        }
    }
    
    /// Attempt to activate a new license key
    public func activate(key: String) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        state = .checking
        updateLastSeenDate()
        
        do {
            let response = try await PolarAPIClient.shared.validate(key: key)
            if response.isActive {
                try saveKeyToKeychain(key)
                defaults.set(Date(), forKey: lastValidationDateKey)
                state = .active
            } else {
                state = .invalid("The provided key is not active.")
            }
        } catch let error as PolarAPIError {
            if case .validationFailed(let msg) = error {
                state = .invalid("Activation failed: \(msg)")
            } else {
                state = .invalid("Activation failed. Please check your internet connection and try again.")
            }
        } catch {
            state = .invalid("Activation failed: Could not save license key securely on your device.")
        }
    }
    
    /// Remove the license key
    public func deactivate() {
        deleteKeyFromKeychain()
        defaults.removeObject(forKey: lastValidationDateKey)
        state = evaluateTrialState()
    }
    
    // MARK: - Internal Evaluation
    
    private func updateLastSeenDate() {
        let now = Date()
        if let lastSeen = defaults.object(forKey: lastSeenDateKey) as? Date {
            // Only update if time is moving forward
            if now > lastSeen {
                defaults.set(now, forKey: lastSeenDateKey)
            }
        } else {
            defaults.set(now, forKey: lastSeenDateKey)
        }
    }
    
    private func evaluateTrialState() -> State {
        let now = Date()
        let effectiveDate = getEffectiveDate(now: now)
        
        if let firstLaunch = defaults.object(forKey: firstLaunchDateKey) as? Date {
            let daysElapsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: effectiveDate).day ?? 0
            
            if daysElapsed < 0 {
                return .expired("System clock error detected. Please correct your system time.")
            }
            
            let daysLeft = max(0, trialDays - daysElapsed)
            if daysLeft > 0 {
                return .trial(daysLeft: daysLeft)
            } else {
                return .expired("Your trial has expired. Please purchase a license to continue.")
            }
        } else {
            defaults.set(effectiveDate, forKey: firstLaunchDateKey)
            return .trial(daysLeft: trialDays)
        }
    }
    
    private func evaluateOfflineGrace() -> State {
        guard let lastValidation = defaults.object(forKey: lastValidationDateKey) as? Date else {
            return .invalid("Could not verify license status.")
        }
        
        let now = Date()
        let effectiveDate = getEffectiveDate(now: now)
        
        let daysOffline = Calendar.current.dateComponents([.day], from: lastValidation, to: effectiveDate).day ?? 0
        
        if daysOffline < 0 {
             return .invalid("System clock error detected. Please connect to the internet to validate your license.")
        }
        
        let daysLeft = max(0, offlineGraceDays - daysOffline)
        
        if daysLeft > 0 {
            Self.log.info("Offline validation fallback. \(daysLeft) days of grace remaining.")
            return .offlineGrace(daysLeft: daysLeft)
        } else {
            return .invalid("Offline grace period expired. Please connect to the internet to validate your license.")
        }
    }
    
    /// Returns the later of `now` or `lastSeenDate` to prevent clock rollback exploits
    private func getEffectiveDate(now: Date) -> Date {
        let lastSeen = defaults.object(forKey: lastSeenDateKey) as? Date ?? now
        return now > lastSeen ? now : lastSeen
    }
    
    // MARK: - Keychain Helpers
    
    private func saveKeyToKeychain(_ key: String) throws {
        let data = key.data(using: .utf8)!
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }
    
    private func loadKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
