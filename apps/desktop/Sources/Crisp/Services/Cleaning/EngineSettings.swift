import Foundation

/// On-disk shape of the user's custom cutting settings.
///
/// Forward-compatible by design: every field decodes with `decodeIfPresent` and
/// falls back to a default, so a file written by an older version (missing a key
/// a newer version added) still loads — the user keeps every value they set, and
/// new keys simply appear at their default. `version` is reserved for any future
/// migration. Mirrors the engine defaults in `crisp/config.py`.
struct EngineConfig: Codable, Equatable {
    var version: Int
    var pauseThreshold: Double
    var silenceFloorDB: Double
    var breathingRoom: Double
    var minKeep: Double

    static let defaults = EngineConfig(
        version: 1, pauseThreshold: 0.35, silenceFloorDB: -30, breathingRoom: 0.10, minKeep: 0.05)

    enum CodingKeys: String, CodingKey {
        case version, pauseThreshold, silenceFloorDB, breathingRoom, minKeep
    }

    init(version: Int, pauseThreshold: Double, silenceFloorDB: Double,
         breathingRoom: Double, minKeep: Double) {
        self.version = version
        self.pauseThreshold = pauseThreshold
        self.silenceFloorDB = silenceFloorDB
        self.breathingRoom = breathingRoom
        self.minKeep = minKeep
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineConfig.defaults
        version        = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        pauseThreshold = try c.decodeIfPresent(Double.self, forKey: .pauseThreshold) ?? d.pauseThreshold
        silenceFloorDB = try c.decodeIfPresent(Double.self, forKey: .silenceFloorDB) ?? d.silenceFloorDB
        breathingRoom  = try c.decodeIfPresent(Double.self, forKey: .breathingRoom) ?? d.breathingRoom
        minKeep        = try c.decodeIfPresent(Double.self, forKey: .minKeep) ?? d.minKeep
    }
}

/// The live, editable custom settings, persisted to a JSON file in the channel's
/// data home (`~/.crisp*/config/settings.json`) — outside the app bundle, so an
/// update never disturbs them. Loads on launch (defaults fill any missing keys);
/// every change is written back atomically.
@MainActor
@Observable
final class EngineSettings {
    var pauseThreshold: Double { didSet { save() } }
    var silenceFloorDB: Double { didSet { save() } }
    var breathingRoom: Double { didSet { save() } }
    var minKeep: Double { didSet { save() } }

    /// A plain-value snapshot of the live settings (used to derive cut parameters).
    var config: EngineConfig {
        EngineConfig(version: EngineConfig.defaults.version,
                     pauseThreshold: pauseThreshold, silenceFloorDB: silenceFloorDB,
                     breathingRoom: breathingRoom, minKeep: minKeep)
    }

    /// `~/.crisp*/config/settings.json` — beside the downloaded model.
    static var fileURL: URL {
        Channel.current.dataDirectory
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    init() {
        let url = Self.fileURL
        let existed = FileManager.default.fileExists(atPath: url.path)
        let cfg = Self.read(from: url)
        // Property observers don't fire for assignments in init, so no save here.
        pauseThreshold = cfg.pauseThreshold
        silenceFloorDB = cfg.silenceFloorDB
        breathingRoom = cfg.breathingRoom
        minKeep = cfg.minKeep
        if !existed { Self.write(config, to: url) }  // materialize the file on first launch
    }

    func restoreDefaults() {
        let d = EngineConfig.defaults
        pauseThreshold = d.pauseThreshold
        silenceFloorDB = d.silenceFloorDB
        breathingRoom = d.breathingRoom
        minKeep = d.minKeep
    }

    private func save() { Self.write(config, to: Self.fileURL) }

    private static func read(from url: URL) -> EngineConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(EngineConfig.self, from: data) else {
            return .defaults
        }
        return cfg
    }

    private static func write(_ cfg: EngineConfig, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(cfg).write(to: url, options: .atomic)
        } catch {
            AppInfo.logger("settings").error("Couldn't save settings: \(error.localizedDescription)")
        }
    }
}
