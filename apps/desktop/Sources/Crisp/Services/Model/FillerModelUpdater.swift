import Foundation
import Observation
import CrispCore

/// Checks Hugging Face for a newer filler model and offers an in-app update — like
/// the app's own updater, but for the model, independent of app releases.
///
/// The model's `config.json` on `main` is the **manifest**: it carries `version` and
/// `model_sha256`. We compare its version to the installed one (read from the local
/// config sidecar). On a newer version we build an `updateSpec` pinned to that version
/// with the manifest's hash, so the downloaded update is verified just like a first
/// install. The caller feeds `updateSpec` to `ModelStore.applyUpdate`.
@MainActor
@Observable
final class FillerModelUpdater {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String)
    }
    private(set) var state: State = .idle
    private(set) var updateSpec: ModelSpec?

    /// Poll the manifest and compare to the installed version. No-op if the model
    /// isn't installed yet (nothing to update). `baseSpec` provides the repo URL +
    /// display fields; `installedVersion` comes from the local config sidecar.
    func check(baseSpec: ModelSpec, installedVersion: String?) async {
        guard let installed = installedVersion else { state = .idle; return }
        state = .checking
        guard let manifestURL = Self.manifestURL(from: baseSpec.url),
              let (data, resp) = try? await URLSession.shared.data(from: manifestURL),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remote = j["version"] as? String,
              let sha = j["model_sha256"] as? String, !sha.isEmpty else {
            state = .idle
            return
        }
        let file = (j["model_file"] as? String) ?? baseSpec.fileName
        guard Self.isNewer(remote, than: installed),
              let url = Self.versionedURL(from: baseSpec.url, version: remote, file: file) else {
            state = .upToDate
            return
        }
        updateSpec = ModelSpec(id: baseSpec.id, fileName: file, url: url, sha256: sha,
                               approxBytes: baseSpec.approxBytes, displayName: baseSpec.displayName,
                               summary: baseSpec.summary, recommended: baseSpec.recommended)
        state = .available(version: remote)
    }

    func clear() { state = .idle; updateSpec = nil }

    /// Apply the found update via `store`: drop the old config sidecar (so the new one
    /// is re-fetched when the model lands), then download + verify the new version.
    /// Shared by the Settings row and the main-window bar.
    func apply(using store: ModelStore) async {
        guard let spec = updateSpec else { return }
        if let path = store.readyModelPath {
            try? FileManager.default.removeItem(at: FillerModelConfig.sidecar(for: path))
        }
        await store.applyUpdate(to: spec)
        clear()
    }

    // MARK: - HF resolve-URL helpers (…/resolve/<ref>/<file>)

    /// …/resolve/<ref>/<Name>.mlmodel → …/resolve/main/<Name>.config.json
    static func manifestURL(from modelURL: URL) -> URL? {
        let cfg = modelURL.deletingPathExtension().lastPathComponent + ".config.json"
        return replacingResolve(modelURL, ref: "main", file: cfg)
    }
    /// …/resolve/<ref>/<file> → …/resolve/v<version>/<file>
    static func versionedURL(from modelURL: URL, version: String, file: String) -> URL? {
        replacingResolve(modelURL, ref: "v\(version)", file: file)
    }
    private static func replacingResolve(_ url: URL, ref: String, file: String) -> URL? {
        var parts = url.pathComponents              // ["/", owner, repo, "resolve", ref, file]
        guard let i = parts.firstIndex(of: "resolve"), i + 2 < parts.count else { return nil }
        parts[i + 1] = ref
        parts[i + 2] = file
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/" + parts.dropFirst().joined(separator: "/")
        return comps?.url
    }

    /// Compare "0.0.N" version strings numerically (the commit-count scheme).
    static func isNewer(_ a: String, than b: String) -> Bool {
        func nums(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let (pa, pb) = (nums(a), nums(b))
        for k in 0..<max(pa.count, pb.count) {
            let x = k < pa.count ? pa[k] : 0, y = k < pb.count ? pb[k] : 0
            if x != y { return x > y }
        }
        return false
    }
}
