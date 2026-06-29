import Foundation

/// Stateless client for Polar.sh's **customer-portal** license endpoints. These are
/// public (no API token) — the only embedded identifier is the organization id
/// (`PolarConfig.organizationID`), which isn't a secret. Networking mirrors
/// `Updater`'s style: `URLSession.shared.data(for:)`, an `HTTPURLResponse` status
/// switch, and small `Decodable` payloads.
public struct PolarService: Sendable {
    public init() {}

    private static let base = URL(string: "https://api.polar.sh")!
    private static let log = AppInfo.logger("polar")

    public struct ValidateResult: Sendable {
        public let granted: Bool
        /// Polar `limit_activations > 0` ⇒ the key is device-bound and must be activated.
        public let requiresActivation: Bool
        public let activationsLimit: Int
    }

    public struct ActivateResult: Sendable {
        public let activationID: String
        public let activationsLimit: Int
    }

    /// Validate a key with no activation context — tells us if it's granted and
    /// whether it requires device activation.
    public func validate(key: String) async throws -> ValidateResult {
        let data = try await post("/v1/customer-portal/license-keys/validate",
                                  body: ["key": key, "organization_id": orgID()])
        let resp = try decode(ValidateResponse.self, from: data)
        let limit = resp.limitActivations ?? 0
        return ValidateResult(granted: resp.status == "granted",
                              requiresActivation: limit > 0,
                              activationsLimit: limit)
    }

    /// Re-validate a device-bound key against its stored activation id.
    public func validate(key: String, activationID: String) async throws -> Bool {
        let data = try await post("/v1/customer-portal/license-keys/validate",
                                  body: ["key": key,
                                         "organization_id": orgID(),
                                         "activation_id": activationID])
        return try decode(ValidateResponse.self, from: data).status == "granted"
    }

    /// Bind a key to this device. `403` ⇒ the activation limit is already reached.
    public func activate(key: String, label: String, deviceID: String) async throws -> ActivateResult {
        let data = try await post("/v1/customer-portal/license-keys/activate",
                                  body: ["key": key,
                                         "organization_id": orgID(),
                                         "label": label,
                                         "meta": ["device_id": deviceID]])
        let resp = try decode(ActivateResponse.self, from: data)
        return ActivateResult(activationID: resp.id,
                              activationsLimit: resp.licenseKey?.limitActivations ?? 0)
    }

    /// Free this device's activation seat (so "Deactivate" actually releases it,
    /// rather than orphaning the Polar record).
    public func deactivate(key: String, activationID: String) async throws {
        _ = try await post("/v1/customer-portal/license-keys/deactivate",
                           body: ["key": key,
                                  "organization_id": orgID(),
                                  "activation_id": activationID])
    }

    // MARK: - Plumbing

    /// The Polar organization id, or a clear error if it wasn't configured at build
    /// time (`CRISP_POLAR_ORG_ID` → `CrispPolarOrgID`) — so a misconfigured build fails
    /// fast instead of sending an empty `organization_id` to Polar.
    private func orgID() throws -> String {
        guard let id = PolarConfig.organizationID, !id.isEmpty else { throw PolarError.notConfigured }
        return id
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PolarError.server(-1) }
        switch http.statusCode {
        case 200...299:      return data
        case 403:            throw PolarError.activationLimitReached
        case 404:            throw PolarError.keyNotFound
        default:             throw PolarError.server(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Surface the real decode failure to the log so a future Polar API change is
            // diagnosable; the caller still gets the clean user-facing `.decoding` message.
            Self.log.error("Polar response decode failed: \(error.localizedDescription, privacy: .public)")
            throw PolarError.decoding
        }
    }
}

// MARK: - Polar response payloads (file-private; flattened to avoid deep nesting)

private struct ValidateResponse: Decodable {
    let status: String
    let limitActivations: Int?
    enum CodingKeys: String, CodingKey {
        case status
        case limitActivations = "limit_activations"
    }
}

private struct ActivateResponse: Decodable {
    let id: String
    let licenseKey: LicenseKeyInfo?
    enum CodingKeys: String, CodingKey {
        case id
        case licenseKey = "license_key"
    }
}

private struct LicenseKeyInfo: Decodable {
    let limitActivations: Int?
    enum CodingKeys: String, CodingKey { case limitActivations = "limit_activations" }
}

/// Errors surfaced by `PolarService`, each with user-facing copy.
public enum PolarError: LocalizedError, Equatable {
    case notConfigured
    case keyNotFound
    case activationLimitReached
    case server(Int)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Licensing isn’t configured in this build. Please contact support."
        case .keyNotFound:
            return "License key not found. Check it for typos, or copy it again from your purchase email."
        case .activationLimitReached:
            return "This license is already active on the maximum number of devices. Deactivate another device in your Polar account, then try again."
        case .server(let code):
            return "Couldn’t reach the license server (error \(code)). Please try again in a moment."
        case .decoding:
            return "The license server returned an unexpected response. Please try again."
        }
    }
}
