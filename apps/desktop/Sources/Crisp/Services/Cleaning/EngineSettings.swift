import Foundation

/// On-disk shape of the user's custom cutting + encoding settings.
///
/// Forward-compatible by design: every field decodes with `decodeIfPresent` and
/// falls back to a default, so a file written by an older version (missing a key
/// a newer version added) still loads — the user keeps every value they set, and
/// new keys simply appear at their default. `version` is reserved for any future
/// migration. Mirrors the engine defaults in `crisp/config.py`.
struct EngineConfig: Codable, Equatable {
    var version: Int
    // Cutting
    var pauseThreshold: Double
    var silenceFloorDB: Double
    var breathingRoom: Double
    var minKeep: Double
    // Encoding
    var videoCodec: String        // "h264" | "hevc"
    var hardwareEncoding: Bool    // Apple VideoToolbox
    var videoQuality: String      // "maximum" | "high" | "balanced" | "smaller"
    var audioCodec: String        // "aac" | "opus"
    var audioBitrateKbps: Int
    // Backup
    var backupOriginal: Bool      // copy the source aside before cutting

    static let defaults = EngineConfig(
        version: 2,
        pauseThreshold: 0.35, silenceFloorDB: -30, breathingRoom: 0.10, minKeep: 0.05,
        videoCodec: "hevc", hardwareEncoding: true, videoQuality: "high",
        audioCodec: "aac", audioBitrateKbps: 192, backupOriginal: true)

    enum CodingKeys: String, CodingKey {
        case version, pauseThreshold, silenceFloorDB, breathingRoom, minKeep
        case videoCodec, hardwareEncoding, videoQuality, audioCodec, audioBitrateKbps
        case backupOriginal
    }

    init(version: Int, pauseThreshold: Double, silenceFloorDB: Double, breathingRoom: Double,
         minKeep: Double, videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
         audioCodec: String, audioBitrateKbps: Int, backupOriginal: Bool) {
        self.version = version
        self.pauseThreshold = pauseThreshold
        self.silenceFloorDB = silenceFloorDB
        self.breathingRoom = breathingRoom
        self.minKeep = minKeep
        self.videoCodec = videoCodec
        self.hardwareEncoding = hardwareEncoding
        self.videoQuality = videoQuality
        self.audioCodec = audioCodec
        self.audioBitrateKbps = audioBitrateKbps
        self.backupOriginal = backupOriginal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineConfig.defaults
        version          = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        pauseThreshold   = try c.decodeIfPresent(Double.self, forKey: .pauseThreshold) ?? d.pauseThreshold
        silenceFloorDB   = try c.decodeIfPresent(Double.self, forKey: .silenceFloorDB) ?? d.silenceFloorDB
        breathingRoom    = try c.decodeIfPresent(Double.self, forKey: .breathingRoom) ?? d.breathingRoom
        minKeep          = try c.decodeIfPresent(Double.self, forKey: .minKeep) ?? d.minKeep
        videoCodec       = try c.decodeIfPresent(String.self, forKey: .videoCodec) ?? d.videoCodec
        hardwareEncoding = try c.decodeIfPresent(Bool.self, forKey: .hardwareEncoding) ?? d.hardwareEncoding
        videoQuality     = try c.decodeIfPresent(String.self, forKey: .videoQuality) ?? d.videoQuality
        audioCodec       = try c.decodeIfPresent(String.self, forKey: .audioCodec) ?? d.audioCodec
        audioBitrateKbps = try c.decodeIfPresent(Int.self, forKey: .audioBitrateKbps) ?? d.audioBitrateKbps
        backupOriginal   = try c.decodeIfPresent(Bool.self, forKey: .backupOriginal) ?? d.backupOriginal
    }
}

/// The live, editable settings, persisted to a JSON file in the channel's data
/// home (`~/.crisp*/config/settings.json`) — outside the app bundle, so an update
/// never disturbs them. Loads on launch (defaults fill any missing keys); every
/// change is written back atomically.
@MainActor
@Observable
final class EngineSettings {
    // Cutting (used by the "Custom" strength)
    var pauseThreshold: Double { didSet { save() } }
    var silenceFloorDB: Double { didSet { save() } }
    var breathingRoom: Double { didSet { save() } }
    var minKeep: Double { didSet { save() } }
    // Encoding (applied to every clean)
    var videoCodec: String { didSet { save() } }
    var hardwareEncoding: Bool { didSet { save() } }
    var videoQuality: String { didSet { save() } }
    var audioCodec: String { didSet { save() } }
    var audioBitrateKbps: Int { didSet { save() } }
    // Backup (applied to every clean)
    var backupOriginal: Bool { didSet { save() } }

    /// A plain-value snapshot of the live settings.
    var config: EngineConfig {
        EngineConfig(version: EngineConfig.defaults.version,
                     pauseThreshold: pauseThreshold, silenceFloorDB: silenceFloorDB,
                     breathingRoom: breathingRoom, minKeep: minKeep,
                     videoCodec: videoCodec, hardwareEncoding: hardwareEncoding,
                     videoQuality: videoQuality, audioCodec: audioCodec,
                     audioBitrateKbps: audioBitrateKbps, backupOriginal: backupOriginal)
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
        videoCodec = cfg.videoCodec
        hardwareEncoding = cfg.hardwareEncoding
        videoQuality = cfg.videoQuality
        audioCodec = cfg.audioCodec
        audioBitrateKbps = cfg.audioBitrateKbps
        backupOriginal = cfg.backupOriginal
        if !existed { Self.write(config, to: url) }  // materialize the file on first launch
    }

    func restoreDefaults() {
        let d = EngineConfig.defaults
        pauseThreshold = d.pauseThreshold
        silenceFloorDB = d.silenceFloorDB
        breathingRoom = d.breathingRoom
        minKeep = d.minKeep
        videoCodec = d.videoCodec
        hardwareEncoding = d.hardwareEncoding
        videoQuality = d.videoQuality
        audioCodec = d.audioCodec
        audioBitrateKbps = d.audioBitrateKbps
        backupOriginal = d.backupOriginal
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
