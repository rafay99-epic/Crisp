import Foundation

/// Reads the extended attribute the engine writes on cleaned files saved to a
/// shared output folder (`crisp/edit.py` sets `user.crisp.source` to the path of
/// the video that produced them). The watch folder uses it to tell its own
/// already-cleaned output apart from a different source's same-named file.
public enum OutputTag {
    /// Must match `SOURCE_XATTR` in `crisp/edit.py`.
    public static let key = "user.crisp.source"

    /// The source path recorded on the file at `path`, or nil if it's untagged or
    /// the filesystem doesn't support extended attributes.
    public static func source(ofFileAt path: String) -> String? {
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, key, &buffer, size, 0, 0)
        guard read >= 0 else { return nil }
        return String(bytes: buffer[0..<read], encoding: .utf8)
    }
}
