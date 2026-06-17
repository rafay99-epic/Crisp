import AppKit
import Foundation

/// Checks GitHub Releases for newer builds, downloads the channel's DMG, and
/// swaps the installed app in place. The repository is private, so requests
/// authenticate with the token from the locally signed-in GitHub CLI
/// (`gh auth token`). Stable tracks the latest release; Nightly tracks the
/// newest pre-release (ordered by CI build number); Dev never updates.
@MainActor
@Observable
final class Updater {
    enum Status: Equatable {
        case idle, checking, upToDate, downloading, installing
        case available(Release)
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let tag: String
        let assetURL: String
        let assetName: String
        var buildNumber: Int = 0
        var displayVersion: String {
            buildNumber > 0 ? "\(version) (build \(buildNumber))" : version
        }
    }

    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    private static let log = AppInfo.logger("updater")
    nonisolated static let repository = "rafay99-epic/Crisp"
    nonisolated static let currentVersion =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    nonisolated static let currentBuildNumber =
        Int(Bundle.main.infoDictionary?["CrispBuildNumber"] as? String ?? "") ?? 0
    nonisolated private static let installPath = Bundle.main.bundlePath
    nonisolated static var assetName: String? { Channel.current.assetName }
    nonisolated static var bundleInImage: String { "\(Channel.current.displayName).app" }

    var isBusy: Bool { status == .checking || status == .downloading || status == .installing }

    /// One automatic check shortly after launch (Stable + Nightly only).
    func checkOnLaunch() {
        guard Channel.current.updatesEnabled else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard Channel.current.updatesEnabled else { status = .idle; return }
        guard !isBusy else { return }
        status = .checking
        do {
            let release = try await Self.fetchLatestRelease()
            lastChecked = Date()
            if let release, Self.isNewer(release) {
                Self.log.notice("update available: \(release.displayVersion, privacy: .public)")
                status = .available(release)
            } else {
                status = .upToDate
            }
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall() async {
        guard case .available(let release) = status else { return }
        status = .downloading
        do {
            let dmg = try await Self.download(release)
            status = .installing
            try await Self.install(dmgAt: dmg)
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/zsh")
            relauncher.arguments = ["-c", "sleep 1; /usr/bin/open '\(Self.installPath)'"]
            try? relauncher.run()
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    nonisolated static func isNewer(_ release: Release) -> Bool {
        switch Channel.current {
        case .stable:  return isVersion(release.version, newerThan: currentVersion)
        case .nightly: return release.buildNumber > currentBuildNumber
        case .dev:     return false
        }
    }

    // MARK: - GitHub API

    private struct APIAsset: Decodable { let name: String; let url: String }
    private struct APIRelease: Decodable {
        let tagName: String
        let name: String?
        let prerelease: Bool?
        let draft: Bool?
        let assets: [APIAsset]
    }

    nonisolated static func fetchLatestRelease() async throws -> Release? {
        guard Channel.current.updatesEnabled else { return nil }
        return Channel.current.isPrerelease
            ? try await fetchLatestPrerelease()
            : try await fetchStableRelease()
    }

    nonisolated private static func fetchStableRelease() async throws -> Release? {
        guard let data = try await get("https://api.github.com/repos/\(repository)/releases/latest")
        else { return nil }
        return release(from: try jsonDecoder().decode(APIRelease.self, from: data))
    }

    nonisolated private static func fetchLatestPrerelease() async throws -> Release? {
        guard let data = try await get("https://api.github.com/repos/\(repository)/releases?per_page=30")
        else { return nil }
        let releases = try jsonDecoder().decode([APIRelease].self, from: data)
        for api in releases where (api.prerelease ?? false) && !(api.draft ?? false) {
            if let release = release(from: api) { return release }
        }
        return nil
    }

    nonisolated private static func get(_ urlString: String) async throws -> Data? {
        let token = githubToken()
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError(message: "Unexpected response from GitHub.")
        }
        switch http.statusCode {
        case 200: return data
        case 404 where token == nil:
            throw UpdateError(message: "Can't see the private repository. Install GitHub CLI and run “gh auth login”.")
        case 404: return nil
        default: throw UpdateError(message: "GitHub returned HTTP \(http.statusCode).")
        }
    }

    nonisolated private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    nonisolated private static func release(from api: APIRelease) -> Release? {
        guard let assetName, let asset = api.assets.first(where: { $0.name == assetName }) else { return nil }
        let version = api.tagName.hasPrefix("v") ? String(api.tagName.dropFirst()) : api.tagName
        return Release(version: version, tag: api.tagName, assetURL: asset.url,
                       assetName: asset.name, buildNumber: buildNumber(in: api.name))
    }

    nonisolated static func buildNumber(in name: String?) -> Int {
        guard let name,
              let range = name.range(of: #"build (\d+)"#, options: .regularExpression) else { return 0 }
        return Int(name[range].dropFirst("build ".count)) ?? 0
    }

    nonisolated static func download(_ release: Release) async throws -> URL {
        guard let assetURL = URL(string: release.assetURL) else {
            throw UpdateError(message: "The release has an invalid download URL.")
        }
        var request = URLRequest(url: assetURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = githubToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (tempFile, response) = try await URLSession.shared.download(for: request, delegate: RedirectSanitizer())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempFile)
            throw UpdateError(message: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Crisp-\(release.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    nonisolated static func install(dmgAt dmg: URL) async throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("crisp-update-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try runTool("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path])
        defer {
            _ = try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: dmg)
        }
        let source = mountPoint.appendingPathComponent(bundleInImage)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError(message: "The update image doesn't contain \(bundleInImage).")
        }
        if FileManager.default.fileExists(atPath: installPath) {
            try FileManager.default.removeItem(atPath: installPath)
        }
        try runTool("/usr/bin/ditto", [source.path, installPath])
    }

    // MARK: - Helpers

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = components(candidate), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let lhs = index < a.count ? a[index] : 0
            let rhs = index < b.count ? b[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    nonisolated static func githubToken() -> String? {
        for gh in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        where FileManager.default.isExecutableFile(atPath: gh) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gh)
            process.arguments = ["auth", "token"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { continue }
            guard waitUntilExit(process, timeout: 10), process.terminationStatus == 0 else { continue }
            let token = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let token, !token.isEmpty { return token }
        }
        return nil
    }

    @discardableResult
    nonisolated private static func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        guard waitUntilExit(process, timeout: 60) else {
            throw UpdateError(message: "\(path) timed out and was stopped.")
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError(message: message.isEmpty ? "\(path) exited with \(process.terminationStatus)" : message)
        }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @discardableResult
    nonisolated private static func waitUntilExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        if !process.isRunning { done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return false
        }
        return true
    }

    private final class RedirectSanitizer: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            var sanitized = request
            sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
            return sanitized
        }
    }
}
