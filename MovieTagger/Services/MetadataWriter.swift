import Foundation

/// Writes MP4 metadata by directly manipulating atoms in-place.
/// No remuxing, no re-encoding, no file copy.  Only the moov atom is touched.
final class MetadataWriter {

    enum WriterError: LocalizedError {
        case cannotReadFile
        case invalidMP4
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotReadFile:    return "Cannot read the input file."
            case .invalidMP4:        return "Not a valid MP4 file (moov atom not found)."
            case .writeFailed(let m): return "Metadata write failed: \(m)"
            }
        }
    }

    // MARK: - Public API

    /// Write metadata directly into the MP4 file (in-place, no remux).
    func writeMetadata(
        fileURL: URL,
        model: MovieEditModel,
        progressHandler: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws {
        await MainActor.run { progressHandler(0.05) }

        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }

        let fileSize = Int(handle.seekToEndOfFile())

        // 1. Scan top-level boxes to locate moov
        let topBoxes = try scanTopLevelBoxes(handle: handle, fileSize: fileSize)

        guard let moovBox = topBoxes.first(where: { $0.type == "moov" }) else {
            throw WriterError.invalidMP4
        }

        await MainActor.run { progressHandler(0.15) }

        // 2. Read moov data (typically < 1 MB, even for big files)
        handle.seek(toFileOffset: UInt64(moovBox.offset))
        guard let moovData = try handle.read(upToCount: moovBox.size),
              moovData.count == moovBox.size else {
            throw WriterError.cannotReadFile
        }

        await MainActor.run { progressHandler(0.30) }

        // 3. Build new ilst atom from the edit model
        let newIlst = buildIlstAtom(from: model)

        // 4. Splice the new ilst into the moov data
        let newMoov = rebuildMoov(original: moovData, newIlst: newIlst)

        await MainActor.run { progressHandler(0.60) }

        // 5. Write back to the file (in-place, no mdat copy)
        let moovEnd = moovBox.offset + moovBox.size
        let isLast  = (moovEnd >= fileSize)

        if isLast {
            // moov is at end of file → truncate & rewrite (instant)
            try handle.truncate(atOffset: UInt64(moovBox.offset))
            handle.seek(toFileOffset: UInt64(moovBox.offset))
            try handle.write(contentsOf: newMoov)
        } else {
            // moov is before mdat → append new moov at EOF, blank old moov with free box
            // Step A: append new moov (old moov still valid if we crash here)
            handle.seekToEndOfFile()
            try handle.write(contentsOf: newMoov)
            // Step B: overwrite old moov space with a free box
            handle.seek(toFileOffset: UInt64(moovBox.offset))
            try handle.write(contentsOf: makeFreeBox(size: moovBox.size))
        }

        try handle.synchronize()
        await MainActor.run { progressHandler(1.0) }
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Top-level box scanning (reads only headers, not payloads)
    // ───────────────────────────────────────────────────────────────────

    private struct FileBox {
        let type: String
        let offset: Int
        let size: Int
    }

    private func scanTopLevelBoxes(handle: FileHandle, fileSize: Int) throws -> [FileBox] {
        var boxes: [FileBox] = []
        var pos = 0

        while pos + 8 <= fileSize {
            handle.seek(toFileOffset: UInt64(pos))
            guard let hdr = try handle.read(upToCount: 8), hdr.count == 8 else { break }

            let hdrBytes = [UInt8](hdr)
            var size = Int(UInt32(hdrBytes[0]) << 24 | UInt32(hdrBytes[1]) << 16
                        | UInt32(hdrBytes[2]) << 8  | UInt32(hdrBytes[3]))
            let type = String(bytes: hdrBytes[4..<8], encoding: .ascii) ?? "????"

            if size == 1 {                                      // 64-bit extended size
                guard let ext = try handle.read(upToCount: 8), ext.count == 8 else { break }
                let extData = Data(ext)               // ensure contiguous
                size = Int(readU64(extData, 0))
            } else if size == 0 {                               // box runs to EOF
                size = fileSize - pos
            }
            guard size >= 8 else { break }

            boxes.append(FileBox(type: type, offset: pos, size: size))
            pos += size
        }
        return boxes
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Moov / udta / meta / ilst rebuild
    //
    // Strategy: walk the container hierarchy, copy every child box as-is
    // EXCEPT the ilst which is replaced with the freshly built one.
    // Parent sizes are recalculated automatically by wrapBox().
    // ───────────────────────────────────────────────────────────────────

    private struct ChildBox {
        let type: String
        let offset: Int        // relative to parent data start
        let size: Int
    }

    /// Parse the child boxes inside a container, starting after `headerSize` bytes.
    private func parseChildren(of data: Data, headerSize: Int) -> [ChildBox] {
        var children: [ChildBox] = []
        let base = data.startIndex
        let total = data.count
        var pos = headerSize

        while pos + 8 <= total {
            let size = Int(readU32(data, pos))
            let typeStart = base + pos + 4
            let type = String(bytes: data[typeStart ..< typeStart + 4], encoding: .ascii) ?? "????"

            let actualSize: Int
            if size == 1, pos + 16 <= total {
                actualSize = Int(readU64(data, pos + 8))
            } else if size == 0 {
                actualSize = total - pos
            } else {
                actualSize = size
            }
            guard actualSize >= 8, pos + actualSize <= total else { break }

            children.append(ChildBox(type: type, offset: pos, size: actualSize))
            pos += actualSize
        }
        return children
    }

    /// Extract a child box's bytes from a parent Data using relative offsets.
    private func childData(_ parent: Data, offset: Int, size: Int) -> Data {
        let base = parent.startIndex
        return Data(parent[(base + offset) ..< (base + offset + size)])
    }

    private func rebuildMoov(original moov: Data, newIlst: Data) -> Data {
        let children = parseChildren(of: moov, headerSize: 8)
        var body = Data()
        var wroteUdta = false

        for child in children {
            if child.type == "udta" {
                wroteUdta = true
                let udta = childData(moov, offset: child.offset, size: child.size)
                body.append(rebuildUdta(original: udta, newIlst: newIlst))
            } else {
                body.append(childData(moov, offset: child.offset, size: child.size))
            }
        }
        if !wroteUdta { body.append(buildFullUdta(ilst: newIlst)) }
        return wrapBox(type: "moov", body: body)
    }

    private func rebuildUdta(original udta: Data, newIlst: Data) -> Data {
        let children = parseChildren(of: udta, headerSize: 8)
        var body = Data()
        var wroteMeta = false

        for child in children {
            if child.type == "meta" {
                wroteMeta = true
                let meta = childData(udta, offset: child.offset, size: child.size)
                body.append(rebuildMeta(original: meta, newIlst: newIlst))
            } else {
                body.append(childData(udta, offset: child.offset, size: child.size))
            }
        }
        if !wroteMeta { body.append(buildFullMeta(ilst: newIlst)) }
        return wrapBox(type: "udta", body: body)
    }

    private func rebuildMeta(original meta: Data, newIlst: Data) -> Data {
        // meta box has 4 extra bytes (version + flags) after the standard 8-byte header
        let metaHeaderSize = 12
        let base = meta.startIndex
        let versionFlags = Data(meta[(base + 8) ..< (base + 12)])

        let children = parseChildren(of: meta, headerSize: metaHeaderSize)
        var body = versionFlags
        var wroteIlst = false
        var hasHdlr = false

        for child in children {
            if child.type == "ilst" {
                wroteIlst = true
                body.append(newIlst)
            } else {
                body.append(childData(meta, offset: child.offset, size: child.size))
                if child.type == "hdlr" { hasHdlr = true }
            }
        }
        if !hasHdlr { body.append(buildMdirHdlr()) }
        if !wroteIlst { body.append(newIlst) }
        return wrapBox(type: "meta", body: body)
    }

    // ───────────────────────────────────────────────────────────────────
    // MARK: - Build new atoms from scratch (when udta/meta don't exist)
    // ───────────────────────────────────────────────────────────────────

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

    private func buildIlstAtom(from model: MovieEditModel) -> Data {
        var body = Data()

        // Title – ©nam  (0xA9 6E 61 6D)
        if !model.title.isEmpty {
            body.append(makeTextItem(type: Data([0xA9, 0x6E, 0x61, 0x6D]), text: model.title))
        }

        // Date / Year – ©day  (0xA9 64 61 79)
        let dateVal = model.releaseDate.isEmpty ? model.year : model.releaseDate
        if !dateVal.isEmpty {
            body.append(makeTextItem(type: Data([0xA9, 0x64, 0x61, 0x79]), text: dateVal))
        }

        // Short description – desc
        if !model.overview.isEmpty {
            body.append(makeTextItem(type: ascii4("desc"), text: model.overview))
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

    private func buildCustomPayload(from model: MovieEditModel) -> Data? {
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
    private func buildITunMOVIPlist(from model: MovieEditModel) -> Data? {
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
