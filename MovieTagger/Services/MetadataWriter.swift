import Foundation

/// Rebuilds movie metadata on a disposable copy and commits atomically.
/// Audio/video bytes and chunk offsets are preserved without re-encoding.
final class MetadataWriter: Sendable {
    enum WriterError: LocalizedError {
        case cannotReadFile
        case invalidMP4
        case unsupported(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotReadFile: return "Cannot read the input file."
            case .invalidMP4: return "The MP4 contains missing, malformed, or truncated atoms. The original file was not changed."
            case .unsupported(let reason): return "This MP4 layout is not supported: \(reason) The original file was not changed."
            case .writeFailed(let message): return "Metadata write failed: \(message)"
            }
        }
    }

    private static let ioQueue = DispatchQueue(label: "com.movietagger.metadata-io", qos: .userInitiated)

    func writeMetadata(
        fileURL: URL,
        metadata: MovieMetadata,
        progressHandler: @escaping @Sendable (Float) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.ioQueue.async {
                do {
                    progressHandler(0.05)
                    try AtomicFileUpdate.perform(at: fileURL) { staged in
                        try self.writeStagedFile(staged, metadata: metadata, progress: progressHandler)
                    }
                    progressHandler(1)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func writeStagedFile(_ url: URL, metadata: MovieMetadata, progress: (Float) -> Void) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        guard let fileSize = Int(exactly: try handle.seekToEnd()) else { throw WriterError.invalidMP4 }
        let boxes = try scanTopLevelBoxes(handle: handle, fileSize: fileSize)
        let moovs = boxes.filter { $0.type == "moov" }
        guard moovs.count == 1, let moov = moovs.first,
              boxes.contains(where: { $0.type == "mdat" }) else { throw WriterError.invalidMP4 }
        guard !boxes.contains(where: { ["moof", "sidx", "mfra"].contains($0.type) }) else {
            throw WriterError.unsupported("fragmented movies")
        }
        // Bound allocation from untrusted input before reading any payload.
        guard moov.size <= 256 * 1024 * 1024 else {
            throw WriterError.unsupported("movie index larger than 256 MB")
        }
        try handle.seek(toOffset: UInt64(moov.offset))
        guard let original = try handle.read(upToCount: moov.size), original.count == moov.size else {
            throw WriterError.cannotReadFile
        }
        progress(0.35)
        let newMoov = try rebuildMoov(original: original, newIlst: buildIlstAtom(from: metadata))
        progress(0.6)

        if moov.offset + moov.size == fileSize {
            // Truncation is safe here: this is only the staged copy.
            try handle.truncate(atOffset: UInt64(moov.offset))
            try handle.seek(toOffset: UInt64(moov.offset))
            try handle.write(contentsOf: newMoov)
        } else {
            // A terminal size=0 box must stop at the OLD EOF, otherwise it
            // would swallow the appended moov. Keep the payload at its offset.
            if let last = boxes.last, last.extendsToEOF {
                guard let finiteSize = UInt32(exactly: last.size) else {
                    throw WriterError.unsupported("an open-ended atom larger than 4 GB")
                }
                try handle.seek(toOffset: UInt64(last.offset))
                var sizeData = Data()
                sizeData.append(bigEndian: finiteSize)
                try handle.write(contentsOf: sizeData)
            }
            try handle.seek(toOffset: UInt64(fileSize))
            try handle.write(contentsOf: newMoov)
            try handle.seek(toOffset: UInt64(moov.offset))
            try handle.write(contentsOf: makeFreeBox(size: moov.size))
        }
        // Verify that exactly one complete moov remains discoverable before commit.
        let end = Int(try handle.seekToEnd())
        let result = try scanTopLevelBoxes(handle: handle, fileSize: end)
        guard result.filter({ $0.type == "moov" }).count == 1 else { throw WriterError.invalidMP4 }
        try handle.synchronize()
        progress(0.9)
    }

    private struct Box {
        let typeBytes: Data
        let offset: Int
        let size: Int
        let headerSize: Int
        let extendsToEOF: Bool
        var type: String { String(data: typeBytes, encoding: .ascii) ?? "????" }
    }

    /// The same checked header parser is used for file and in-memory boxes.
    private func parseHeader(_ data: Data, offset: Int, available: Int) throws -> Box {
        guard available >= 8, data.count >= 8 else { throw WriterError.invalidMP4 }
        let size32 = readU32(data, 0)
        let headerSize = size32 == 1 ? 16 : 8
        guard available >= headerSize, data.count >= headerSize else { throw WriterError.invalidMP4 }
        let size: Int
        if size32 == 1 {
            guard let value = Int(exactly: readU64(data, 8)) else { throw WriterError.invalidMP4 }
            size = value
        } else {
            size = size32 == 0 ? available : Int(size32)
        }
        guard size >= headerSize, size <= available else { throw WriterError.invalidMP4 }
        return Box(typeBytes: childData(data, offset: 4, size: 4), offset: offset,
                   size: size, headerSize: headerSize, extendsToEOF: size32 == 0)
    }

    private func scanTopLevelBoxes(handle: FileHandle, fileSize: Int) throws -> [Box] {
        var boxes: [Box] = []
        var pos = 0
        while pos < fileSize {
            try handle.seek(toOffset: UInt64(pos))
            guard let data = try handle.read(upToCount: min(16, fileSize - pos)) else {
                throw WriterError.cannotReadFile
            }
            let box = try parseHeader(data, offset: pos, available: fileSize - pos)
            boxes.append(box)
            pos += box.size
        }
        return boxes
    }

    private func headerSize(of data: Data) throws -> Int {
        try parseHeader(data, offset: 0, available: data.count).headerSize
    }

    private func parseChildren(of data: Data, headerSize: Int) throws -> [Box] {
        guard headerSize <= data.count else { throw WriterError.invalidMP4 }
        var boxes: [Box] = []
        var pos = headerSize
        while pos < data.count {
            let remaining = data.count - pos
            let header = childData(data, offset: pos, size: min(16, remaining))
            let box = try parseHeader(header, offset: pos, available: remaining)
            boxes.append(box)
            pos += box.size
        }
        return boxes
    }

    private func childData(_ parent: Data, offset: Int, size: Int) -> Data {
        let base = parent.startIndex
        return Data(parent[(base + offset)..<(base + offset + size)])
    }

    private func preservedChild(_ parent: Data, _ box: Box) -> Data {
        var data = childData(parent, offset: box.offset, size: box.size)
        // Appending new siblings must not extend a formerly terminal child.
        if box.extendsToEOF {
            var size = UInt32(box.size).bigEndian
            withUnsafeBytes(of: &size) { data.replaceSubrange(0..<4, with: $0) }
        }
        return data
    }

    private func rebuildMoov(original moov: Data, newIlst: Data) throws -> Data {
        let children = try parseChildren(of: moov, headerSize: headerSize(of: moov))
        guard !children.contains(where: { $0.type == "mvex" }) else {
            throw WriterError.unsupported("fragmented movies")
        }
        var body = Data()
        var wroteUdta = false
        for child in children {
            if child.type == "udta" {
                wroteUdta = true
                body.append(try rebuildUdta(original: preservedChild(moov, child), newIlst: newIlst))
            } else {
                body.append(preservedChild(moov, child))
            }
        }
        if !wroteUdta { body.append(buildFullUdta(ilst: newIlst)) }
        return wrapBox(type: "moov", body: body)
    }

    private func rebuildUdta(original udta: Data, newIlst: Data) throws -> Data {
        let children = try parseChildren(of: udta, headerSize: headerSize(of: udta))
        var body = Data()
        var wroteMeta = false
        for child in children {
            if child.type == "meta" {
                wroteMeta = true
                body.append(try rebuildMeta(original: preservedChild(udta, child), newIlst: newIlst))
            } else {
                body.append(preservedChild(udta, child))
            }
        }
        if !wroteMeta { body.append(buildFullMeta(ilst: newIlst)) }
        return wrapBox(type: "udta", body: body)
    }

    private func rebuildMeta(original meta: Data, newIlst: Data) throws -> Data {
        let header = try headerSize(of: meta)
        let children = try parseChildren(of: meta, headerSize: header + 4)
        var body = childData(meta, offset: header, size: 4)
        var wroteIlst = false
        var hasHdlr = false
        for child in children {
            if child.type == "ilst" {
                wroteIlst = true
                body.append(try mergeIlst(original: preservedChild(meta, child), newIlst: newIlst))
            } else {
                if child.type == "hdlr" {
                    let handler = preservedChild(meta, child)
                    guard handler.count >= child.headerSize + 12,
                          childData(handler, offset: child.headerSize + 8, size: 4) == ascii4("mdir") else {
                        throw WriterError.unsupported("a non-iTunes metadata handler")
                    }
                    hasHdlr = true
                }
                body.append(preservedChild(meta, child))
            }
        }
        if !hasHdlr { body.append(buildMdirHdlr()) }
        if !wroteIlst { body.append(newIlst) }
        return wrapBox(type: "meta", body: body)
    }

    /// Replace only fields owned by MovieTagger; retain all unrelated atoms,
    /// including freeforms distinguished by BOTH their namespace and name.
    private func mergeIlst(original: Data, newIlst: Data) throws -> Data {
        let replacements = try parseChildren(of: newIlst, headerSize: headerSize(of: newIlst))
        var managed = Set(["desc", "ldes", "stik", "hdvd", "gnre"].map(ascii4))
        for suffix in ["nam", "day", "gen", "cmt"] {
            managed.insert(Data([0xA9]) + Data(suffix.utf8))
        }
        // A still-loading/missing poster must not erase existing artwork.
        if replacements.contains(where: { $0.type == "covr" }) { managed.insert(ascii4("covr")) }
        var body = Data()
        for child in try parseChildren(of: original, headerSize: headerSize(of: original)) {
            let data = preservedChild(original, child)
            if managed.contains(child.typeBytes) { continue }
            if child.type == "----" {
                var values: [String: String] = [:]
                for field in try parseChildren(of: data, headerSize: headerSize(of: data)) {
                    if field.type == "mean" || field.type == "name" {
                        guard field.size >= field.headerSize + 4 else { throw WriterError.invalidMP4 }
                        values[field.type] = String(data: childData(data, offset: field.offset + field.headerSize + 4,
                            size: field.size - field.headerSize - 4), encoding: .utf8)
                    }
                }
                if values["mean"] == "com.apple.iTunes", ["iTunEXTC", "iTunMOVI"].contains(values["name"] ?? "") { continue }
                if values["mean"] == "com.movietagger", values["name"] == "tmdb_json" { continue }
            }
            body.append(data)
        }
        body.append(newIlst.dropFirst(try headerSize(of: newIlst)))
        return wrapBox(type: "ilst", body: body)
    }

    private func buildFullUdta(ilst: Data) -> Data {
        return wrapBox(type: "udta", body: buildFullMeta(ilst: ilst))
    }

    private func buildFullMeta(ilst: Data) -> Data {
        var body = Data(count: 4)           // version + flags = 0
        body.append(buildMdirHdlr())
        body.append(ilst)
        return wrapBox(type: "meta", body: body)
    }

    /// Handler reference box declaring "mdir" (metadata directory).
    private func buildMdirHdlr() -> Data {
        var body = Data(count: 4)            // version + flags
        body.append(Data(count: 4))          // pre-defined
        body.append("mdir".data(using: .ascii)!)  // handler type
        body.append("appl".data(using: .ascii)!)  // reserved 1
        body.append(Data(count: 8))               // reserved 2 & 3
        body.append(Data([0]))                     // name (empty C string)
        return wrapBox(type: "hdlr", body: body)
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Build ilst atom from MovieEditModel
    // ───────────────────────────────────────────────────────────────────

    private func buildIlstAtom(from model: MovieMetadata) -> Data {
        var body = Data()

        // Title – ©nam  (0xA9 6E 61 6D)
        if !model.title.isEmpty {
            body.append(makeTextItem(type: Data([0xA9, 0x6E, 0x61, 0x6D]), text: model.title))
        }

        // Date / Year – ©day  (0xA9 64 61 79)
        let dateVal = model.releaseDate
        if !dateVal.isEmpty {
            body.append(makeTextItem(type: Data([0xA9, 0x64, 0x61, 0x79]), text: dateVal))
        }

        // Short description – desc
        if !model.overview.isEmpty {
            body.append(makeTextItem(type: ascii4("desc"), text: String(model.overview.prefix(255))))
        }

        // Long description – ldes
        if !model.overview.isEmpty {
            body.append(makeTextItem(type: ascii4("ldes"), text: model.overview))
        }

        // Genre – ©gen  (0xA9 67 65 6E)
        if !model.genres.isEmpty {
            body.append(makeTextItem(
                type: Data([0xA9, 0x67, 0x65, 0x6E]),
                text: model.genres.joined(separator: ", ")
            ))
        }

        // Comment / tagline – ©cmt  (0xA9 63 6D 74)
        if !model.tagline.isEmpty {
            body.append(makeTextItem(type: Data([0xA9, 0x63, 0x6D, 0x74]), text: model.tagline))
        }

        // Cover art – covr
        if let posterData = model.posterImageData {
            body.append(makeImageItem(imageData: posterData))
        }

        // Media Kind – stik (9 = Movie)
        body.append(makeByteItem(type: ascii4("stik"), value: 9))

        // HD Video – hdvd (0=SD, 1=720p, 2=1080p, 3=4K)
        body.append(makeByteItem(type: ascii4("hdvd"), value: model.resolution.hdvdValue))

        // Content rating – iTunEXTC freeform atom (e.g. "us-tv|PG-13|300|")
        if !model.contentRating.isEmpty {
            let ratingString = "mpaa|\(model.contentRating)|300|"
            body.append(makeFreeformItem(
                mean: "com.apple.iTunes",
                name: "iTunEXTC",
                value: ratingString.data(using: .utf8)!
            ))
        }

        // iTunMOVI plist – cast, directors, screenwriters, producers, studio
        if let moviplist = buildITunMOVIPlist(from: model) {
            body.append(makeFreeformItem(
                mean: "com.apple.iTunes",
                name: "iTunMOVI",
                value: moviplist
            ))
        }

        // TMDb JSON payload – freeform (----) atom
        if let payload = buildCustomPayload(from: model) {
            body.append(makeFreeformItem(
                mean: "com.movietagger",
                name: "tmdb_json",
                value: payload
            ))
        }

        return wrapBox(type: "ilst", body: body)
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - ilst item builders
    // ───────────────────────────────────────────────────────────────────

    /// Standard text item:  [box: type] → [data atom: UTF-8]
    private func makeTextItem(type: Data, text: String) -> Data {
        let utf8 = text.data(using: .utf8)!
        let dataAtom = makeDataAtom(typeIndicator: 1, payload: utf8)
        return wrapBoxRaw(type: type, body: dataAtom)
    }

    /// Cover art item:  [box: "covr"] → [data atom: JPEG or PNG]
    private func makeImageItem(imageData: Data) -> Data {
        let typeInd: UInt32 = detectImageType(imageData)
        let dataAtom = makeDataAtom(typeIndicator: typeInd, payload: imageData)
        return wrapBoxRaw(type: ascii4("covr"), body: dataAtom)
    }

    /// Single-byte integer item (e.g. stik for media kind).
    private func makeByteItem(type: Data, value: UInt8) -> Data {
        let dataAtom = makeDataAtom(typeIndicator: 21, payload: Data([value]))
        return wrapBoxRaw(type: type, body: dataAtom)
    }

    /// Freeform (----) item with mean + name + data sub-atoms.
    private func makeFreeformItem(mean: String, name: String, value: Data) -> Data {
        var body = Data()

        // mean sub-atom
        var meanBody = Data(count: 4)       // version + flags
        meanBody.append(mean.data(using: .utf8)!)
        body.append(wrapBox(type: "mean", body: meanBody))

        // name sub-atom
        var nameBody = Data(count: 4)
        nameBody.append(name.data(using: .utf8)!)
        body.append(wrapBox(type: "name", body: nameBody))

        // data sub-atom
        body.append(makeDataAtom(typeIndicator: 1, payload: value))

        return wrapBox(type: "----", body: body)
    }

    /// Build a `data` atom:  [size][data][typeIndicator][locale][payload]
    private func makeDataAtom(typeIndicator: UInt32, payload: Data) -> Data {
        let size = UInt32(16 + payload.count)
        var d = Data(capacity: Int(size))
        d.append(bigEndian: size)
        d.append(ascii4("data"))
        d.append(bigEndian: typeIndicator)
        d.append(bigEndian: UInt32(0))      // locale
        d.append(payload)
        return d
    }

    private func detectImageType(_ data: Data) -> UInt32 {
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF { return 13 } // JPEG
        if data.count >= 4, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 { return 14 } // PNG
        return 13
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Custom JSON payload
    // ───────────────────────────────────────────────────────────────────

    private func buildCustomPayload(from model: MovieMetadata) -> Data? {
        var dict: [String: Any] = [
            "title":             model.title,
            "year":              model.year,
            "overview":          model.overview,
            "tmdb_id":           model.tmdbId,
            "imdb_id":           model.imdbId,
            "genres":            model.genres,
            "runtime":           model.runtime,
            "tagline":           model.tagline,
            "original_title":    model.originalTitle,
            "original_language": model.originalLanguage,
            "release_date":      model.releaseDate,
            "vote_average":      model.voteAverage,
            "poster_url":        model.posterURL ?? "",
            "fetch_timestamp":   ISO8601DateFormatter().string(from: Date())
        ]
        if let raw = model.rawDetailsJSON,
           let obj = try? JSONSerialization.jsonObject(with: raw) {
            dict["raw_tmdb_response"] = obj
        }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - iTunMOVI plist builder
    // ───────────────────────────────────────────────────────────────────

    /// Build an XML plist for the iTunMOVI atom containing cast, directors,
    /// screenwriters, producers, and studio in Apple's expected format.
    private func buildITunMOVIPlist(from model: MovieMetadata) -> Data? {
        var dict: [String: Any] = [:]

        if !model.cast.isEmpty {
            dict["cast"] = model.cast.map { ["name": $0] }
        }
        if !model.directors.isEmpty {
            dict["directors"] = model.directors.map { ["name": $0] }
        }
        if !model.screenwriters.isEmpty {
            dict["screenwriters"] = model.screenwriters.map { ["name": $0] }
        }
        if !model.producers.isEmpty {
            dict["producers"] = model.producers.map { ["name": $0] }
        }
        if !model.studio.isEmpty {
            dict["studio"] = model.studio
        }

        guard !dict.isEmpty else { return nil }

        return try? PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Low-level helpers
    // ───────────────────────────────────────────────────────────────────

    /// Wrap body bytes in a standard 32-bit box: [size][type][body]
    private func wrapBox(type: String, body: Data) -> Data {
        return wrapBoxRaw(type: type.data(using: .ascii)!, body: body)
    }

    private func wrapBoxRaw(type: Data, body: Data) -> Data {
        let size = UInt32(8 + body.count)
        var d = Data(capacity: Int(size))
        d.append(bigEndian: size)
        d.append(type)
        d.append(body)
        return d
    }

    /// Create a `free` box of exactly `size` bytes (fills old moov space).
    private func makeFreeBox(size: Int) -> Data {
        var d = Data(count: size)
        let s = UInt32(size)
        withUnsafeBytes(of: s.bigEndian) { d.replaceSubrange(0..<4, with: $0) }
        let tag: [UInt8] = [0x66, 0x72, 0x65, 0x65]    // "free"
        d.replaceSubrange(4..<8, with: tag)
        return d
    }

    // ── Binary readers (byte-by-byte, alignment-safe, slice-safe) ──

    private func readU32(_ d: Data, _ off: Int) -> UInt32 {
        let i = d.startIndex + off
        guard i + 4 <= d.endIndex else { return 0 }
        return UInt32(d[i]) << 24
             | UInt32(d[i+1]) << 16
             | UInt32(d[i+2]) << 8
             | UInt32(d[i+3])
    }

    private func readU64(_ d: Data, _ off: Int) -> UInt64 {
        let i = d.startIndex + off
        guard i + 8 <= d.endIndex else { return 0 }
        return UInt64(d[i])   << 56
             | UInt64(d[i+1]) << 48
             | UInt64(d[i+2]) << 40
             | UInt64(d[i+3]) << 32
             | UInt64(d[i+4]) << 24
             | UInt64(d[i+5]) << 16
             | UInt64(d[i+6]) << 8
             | UInt64(d[i+7])
    }

    private func ascii4(_ s: String) -> Data { s.data(using: .ascii)! }
}

// ───────────────────────────────────────────────────────────────────
// MARK: - Data helpers
// ───────────────────────────────────────────────────────────────────

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 4))
    }
}
