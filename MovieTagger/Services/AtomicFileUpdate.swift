import Foundation
import Darwin

/// Edits a same-volume copy, leaving the original intact until an atomic rename.
/// A failed edit (including disk-full) can only damage the disposable copy.
enum AtomicFileUpdate {
    static func perform(at url: URL, edit: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let source = url.resolvingSymlinksInPath()
        let before = try fm.attributesOfItem(atPath: source.path)
        guard before[.type] as? FileAttributeType == .typeRegular else {
            throw MetadataWriter.WriterError.writeFailed("The selected file is not a regular file.")
        }
        let directory = source.deletingLastPathComponent()
            .appendingPathComponent(".movietagger-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let staged = directory.appendingPathComponent(source.lastPathComponent)

        // clonefile preserves attributes and uses copy-on-write on APFS. Other
        // filesystems fall back to a normal copy; both retain media byte offsets.
        if clonefile(source.path, staged.path, 0) != 0 {
            try fm.copyItem(at: source, to: staged)
        }
        try edit(staged)
        let handle = try FileHandle(forUpdating: staged)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        // Don't knowingly overwrite a file another program changed while the
        // copy was being prepared (especially important on slow network volumes).
        let after = try fm.attributesOfItem(atPath: source.path)
        for key: FileAttributeKey in [.systemFileNumber, .size, .modificationDate] {
            guard let a = before[key] as? NSObject, let b = after[key] as? NSObject,
                  a.isEqual(b) else {
                throw MetadataWriter.WriterError.writeFailed("The source file changed during the write. Please try again.")
            }
        }
        guard Darwin.rename(staged.path, source.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
