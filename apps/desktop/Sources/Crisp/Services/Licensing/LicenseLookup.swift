import Foundation
import CrispCore

/// Resolves a Polar `checkout_id` to its license key via the deployed serverless
/// lookup function (`PolarConfig.licenseLookupURL`). The Polar API token lives in that
/// function — this client just does a plain GET and reads back `{ "key": "…" }`, so no
/// secret is embedded in the app.
struct LicenseLookup {
    enum LookupError: LocalizedError {
        case notConfigured
        case notFound
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Automatic activation isn’t set up yet."
            case .notFound:      return "We couldn’t find your license for that purchase yet."
            case .server(let code): return "License lookup failed (error \(code))."
            }
        }
    }

    func key(forCheckout checkoutID: String) async throws -> String {
        guard let base = PolarConfig.licenseLookupURL,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw LookupError.notConfigured
        }
        comps.queryItems = [URLQueryItem(name: "checkout_id", value: checkoutID)]
        guard let url = comps.url else { throw LookupError.notConfigured }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw LookupError.server(-1) }
        switch http.statusCode {
        case 200:        break
        case 404:        throw LookupError.notFound
        default:         throw LookupError.server(http.statusCode)
        }
        return try JSONDecoder().decode(KeyResponse.self, from: data).key
    }

    private struct KeyResponse: Decodable { let key: String }
}
