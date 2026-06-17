import os

/// App-wide identity shared across services, so cross-cutting constants live in
/// one place instead of being re-typed per file.
enum AppInfo {
    /// The stable bundle-id base. Channels append a suffix to form their own id
    /// (see `Channel.bundleSuffix`), but this base is the unified logging
    /// subsystem so every category logs under one roof.
    static let bundleIdentifier = "com.syntaxlabtechnology.crisp"

    /// A `Logger` for `category` under the shared subsystem.
    static func logger(_ category: String) -> Logger {
        Logger(subsystem: bundleIdentifier, category: category)
    }
}
