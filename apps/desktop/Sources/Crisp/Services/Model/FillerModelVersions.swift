import Foundation
import Observation
import CrispCore

/// Dev-only: lists every published version of a filler model (the `v0.0.N` tags on
/// Hugging Face) and installs any of them — the git-history equivalent for models,
/// so you can A/B an old model against a new one in the Dev build.
///
/// The full history already lives server-side (each publish is an immutable tag), so
/// this just enumerates the repo's tags via the HF refs API and pins an install to
/// the chosen one, reusing `FillerModelUpdater.versionedURL` + `ModelStore.applyUpdate`
/// — the same verified download path as a normal update.
@MainActor
@Observable
final class FillerModelVersions {
    /// Published versions, newest first (e.g. ["0.0.8", "0.0.7", …]).
    private(set) var versions: [String] = []
    private(set) var isLoading = false

    /// Fetch the tag list for the model's repo. Best-effort: leaves `versions` empty
    /// on any failure (dev tool, non-critical). Derives the API URL from the model URL.
    func load(repoModelURL: URL) async {
        guard let url = Self.refsURL(from: repoModelURL) else { return }
        isLoading = true
        defer { isLoading = false }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = j["tags"] as? [[String: Any]] else { return }
        versions = tags.compactMap { $0["name"] as? String }
            .filter { $0.hasPrefix("v") }
            .map { String($0.dropFirst()) }                       // "v0.0.8" → "0.0.8"
            .sorted { FillerModelUpdater.isNewer($0, than: $1) }  // newest first
    }

    /// Install a specific version into `store`, verified against that version's own
    /// `config.json` manifest (its `model_sha256`). Drops the config sidecar first so
    /// the new version's per-model values are re-fetched. Returns false if the version's
    /// manifest couldn't be resolved.
    @discardableResult
    func install(version: String, baseSpec: ModelSpec, store: ModelStore) async -> Bool {
        guard let cfgURL = FillerModelUpdater.versionedURL(
                from: baseSpec.url, version: version, file: baseSpec.fileName)
                .flatMap({ $0.deletingPathExtension().appendingPathExtension("config.json") }),
              let (data, resp) = try? await URLSession.shared.data(from: cfgURL),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = j["model_sha256"] as? String, !sha.isEmpty else { return false }
        let file = (j["model_file"] as? String) ?? baseSpec.fileName
        guard let modelURL = FillerModelUpdater.versionedURL(
                from: baseSpec.url, version: version, file: file) else { return false }
        let spec = ModelSpec(id: baseSpec.id, fileName: file, url: modelURL, sha256: sha,
                             approxBytes: baseSpec.approxBytes, displayName: baseSpec.displayName,
                             summary: baseSpec.summary, recommended: baseSpec.recommended)
        if let path = store.readyModelPath {
            try? FileManager.default.removeItem(at: FillerModelConfig.sidecar(for: path))
        }
        await store.applyUpdate(to: spec)
        return true
    }

    /// …/resolve/<ref>/<file> → …/api/models/<owner>/<repo>/refs
    nonisolated static func refsURL(from modelURL: URL) -> URL? {
        let parts = modelURL.pathComponents            // ["/", owner, repo, "resolve", …]
        guard parts.count >= 3 else { return nil }
        var comps = URLComponents(url: modelURL, resolvingAgainstBaseURL: false)
        comps?.path = "/api/models/\(parts[1])/\(parts[2])/refs"
        comps?.query = nil
        return comps?.url
    }
}
