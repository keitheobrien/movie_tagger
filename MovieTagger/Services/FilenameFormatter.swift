import Foundation

struct FilenameFormatter {

    /// Apply the naming pattern with token substitution, sanitize, and add .mp4 extension.
    func format(pattern: String, model: MovieEditModel) -> String {
        var result = pattern
        result = result.replacingOccurrences(of: "{title}",   with: model.title)
        result = result.replacingOccurrences(of: "{year}",    with: model.year)
        result = result.replacingOccurrences(of: "{tmdb_id}", with: model.tmdbId)
        result = result.replacingOccurrences(of: "{imdb_id}", with: model.imdbId)
        return sanitize(result) + ".mp4"
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
    func resolveCollision(directoryURL: URL, desiredName: String) -> URL {
        let fm = FileManager.default
        var url = directoryURL.appendingPathComponent(desiredName)
        guard fm.fileExists(atPath: url.path) else { return url }

        let stem = (desiredName as NSString).deletingPathExtension
        let ext  = (desiredName as NSString).pathExtension

        var counter = 1
        repeat {
            let name = "\(stem) (\(counter)).\(ext)"
            url = directoryURL.appendingPathComponent(name)
            counter += 1
        } while fm.fileExists(atPath: url.path)

        return url
    }
}
