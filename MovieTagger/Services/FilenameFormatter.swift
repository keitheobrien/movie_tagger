import Foundation

struct FilenameFormatter {

    /// Apply the naming pattern with token substitution, sanitize, and add .mp4 extension.
    /// Returns nil when the pattern yields an empty filename (blank pattern, or a
    /// pattern whose tokens all substitute to nothing) — callers must skip renaming
    /// rather than produce an invisible ".mp4" dotfile.
    func formatIfValid(pattern: String, model: MovieEditModel) -> String? {
        var result = pattern
        result = result.replacingOccurrences(of: "{title}",   with: model.title)
        result = result.replacingOccurrences(of: "{year}",    with: model.year)
        result = result.replacingOccurrences(of: "{tmdb_id}", with: model.tmdbId)
        result = result.replacingOccurrences(of: "{imdb_id}", with: model.imdbId)
        let stem = sanitize(result)
        guard !stem.isEmpty else { return nil }
        return stem + ".mp4"
    }

    /// Remove characters that are invalid on macOS file paths.
    func sanitize(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ":", with: " -")
        // Strip control characters (< 0x20) except common whitespace
        s = s.unicodeScalars
            .filter { $0.value >= 32 && !$0.properties.isDefaultIgnorableCodePoint }
            .map { String($0) }
            .joined()
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix(".") {
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// If `desiredName` already exists in `directory`, append " (1)", " (2)", etc.
    /// Pass the file being renamed as `excluding` so that a file already named per
    /// the pattern doesn't collide with itself and get pointlessly bumped to " (1)".
    func resolveCollision(directoryURL: URL, desiredName: String, excluding sourceURL: URL? = nil) -> URL {
        let fm = FileManager.default

        func isSource(_ candidate: URL) -> Bool {
            guard let source = sourceURL else { return false }
            if candidate.standardizedFileURL.path == source.standardizedFileURL.path {
                return true
            }
            // Same file reached via a different spelling (e.g. only case differs on a
            // case-insensitive volume): compare filesystem identity of what's on disk.
            guard
                let idA = try? candidate.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
                let idB = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
                let a = idA as? NSObject, let b = idB as? NSObject
            else { return false }
            return a.isEqual(b)
        }

        var url = directoryURL.appendingPathComponent(desiredName)
        guard fm.fileExists(atPath: url.path), !isSource(url) else { return url }

        let stem = (desiredName as NSString).deletingPathExtension
        let ext  = (desiredName as NSString).pathExtension

        var counter = 1
        repeat {
            let name = "\(stem) (\(counter)).\(ext)"
            url = directoryURL.appendingPathComponent(name)
            counter += 1
        } while fm.fileExists(atPath: url.path) && !isSource(url)

        return url
    }
}
