import Foundation
@testable import MovieTagger

// Independent fixture encoder/decoder: assertions don't use the writer's parser.
enum MP4Fixtures {
    static func uint32(_ n: UInt32) -> Data {
        var value = n.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func uint64(_ n: UInt64) -> Data {
        var value = n.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func box(_ type: String, _ body: Data = Data(), extended: Bool = false, eof: Bool = false) -> Data {
        let tag = type.data(using: .isoLatin1)!
        if extended { return uint32(1) + tag + uint64(UInt64(body.count + 16)) + body }
        return uint32(eof ? 0 : UInt32(body.count + 8)) + tag + body
    }
    static func freeform(_ mean: String, _ name: String, value: String) -> Data {
        box("----", box("mean", Data(count: 4) + Data(mean.utf8))
            + box("name", Data(count: 4) + Data(name.utf8))
            + box("data", uint32(1) + uint32(0) + Data(value.utf8)))
    }
    static func text(_ tag: String, _ value: String) -> Data {
        box(tag, box("data", uint32(1) + uint32(0) + Data(value.utf8)))
    }
    static let media = Data((0..<255).map(UInt8.init))
    static let track = box("trak", box("mdia", Data("SAMPLE_TABLE_MUST_SURVIVE".utf8)))
    static let ftyp = box("ftyp", Data("isom0000".utf8))

    struct Atom {
        let type: String
        let offset: Int
        let size: Int
        let header: Int
        let data: Data
        var body: Data { Data(data.dropFirst(header)) }
    }
    static func atoms(_ data: Data) throws -> [Atom] {
        var offset = 0
        var result: [Atom] = []
        while offset < data.count {
            guard data.count - offset >= 8 else { throw FixtureError.invalid }
            let short = data[offset..<offset+4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let header = short == 1 ? 16 : 8
            guard data.count - offset >= header else { throw FixtureError.invalid }
            let size64 = short == 1 ? data[offset+8..<offset+16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) } : short
            let size = size64 == 0 ? data.count - offset : Int(size64)
            guard size >= header, size <= data.count - offset else { throw FixtureError.invalid }
            result.append(Atom(type: String(data: data[offset+4..<offset+8], encoding: .isoLatin1)!,
                offset: offset, size: size, header: header, data: Data(data[offset..<offset+size])))
            offset += size
        }
        return result
    }
    static func ilst(_ data: Data) throws -> [Atom] {
        let moov = try atoms(data).first { $0.type == "moov" }!
        let udta = try atoms(moov.body).first { $0.type == "udta" }!
        let meta = try atoms(udta.body).first { $0.type == "meta" }!
        let ilst = try atoms(Data(meta.body.dropFirst(4))).first { $0.type == "ilst" }!
        return try atoms(ilst.body)
    }
    enum FixtureError: Error { case invalid }

    @MainActor static func model() throws -> MovieEditModel {
        let json = Data(#"{"id":1,"title":"Fixture","release_date":"1994-09-23","overview":"Test movie"}"#.utf8)
        let model = MovieEditModel(from: try JSONDecoder().decode(TMDbMovieDetails.self, from: json))
        model.renameFile = false
        return model
    }
}
