import Foundation

/// Dev-only sideload of a filler model from disk — the ML equivalent of `./dev.sh`:
/// run a model you just trained **before** publishing anything to Hugging Face.
///
/// Resolution order (dev build only; a no-op on Stable/Nightly):
///   1. the `CRISP_FILLER_MODEL` environment variable — for scripted runs
///      (`CRISP_FILLER_MODEL=…/Wren.mlmodel open 'Crisp Dev.app'`);
///   2. a path picked in Settings → Filler detection → "Load local model…".
///
/// When set, the app runs this file instead of the downloaded model — gating,
/// engine `--filler-model`, and the per-model `…/Wren.config.json` sidecar (read by
/// the `crisp-filler` helper) all follow it. Place a matching `<name>.config.json`
/// beside the `.mlmodel` (export_coreml writes one) so framing/threshold travel too.
public enum DevFillerModel {
    /// The env var a scripted dev run can set to point at a local model.
    public static let envKey = "CRISP_FILLER_MODEL"
    private static let defaultsKey = "devLocalFillerModelPath"

    /// Whether the dev sideload affordance is offered at all (dev build only).
    public static var isAvailable: Bool { Channel.current.showsModelDevTools }

    /// The path the user picked in Settings (persisted), or nil. Settable so the
    /// picker can store / clear it. Independent of whether it currently exists.
    public static var pickedPath: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The resolved local model to run instead of the downloaded one — env var first,
    /// then the picked path — but only on dev and only if the file actually exists
    /// (a stale picked path silently falls back to the normal downloaded model).
    public static var overridePath: String? {
        guard isAvailable else { return nil }
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment[envKey],
           !env.isEmpty, fm.fileExists(atPath: env) { return env }
        if let picked = pickedPath, !picked.isEmpty, fm.fileExists(atPath: picked) { return picked }
        return nil
    }

    /// True when the active override came from the environment (so the UI can show
    /// it's env-driven and not offer to clear it — only the env var can).
    public static var isEnvOverride: Bool {
        guard isAvailable, let env = ProcessInfo.processInfo.environment[envKey], !env.isEmpty
        else { return false }
        return FileManager.default.fileExists(atPath: env)
    }
}
