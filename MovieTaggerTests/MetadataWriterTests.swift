import XCTest
@testable import MovieTagger

final class MetadataWriterTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func write(_ input: Data, metadata: MovieMetadata) async throws -> Data {
        let url = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        try input.write(to: url)
        try await MetadataWriter().writeMetadata(fileURL: url, metadata: metadata, progressHandler: { _ in })
        return try Data(contentsOf: url)
    }

    @MainActor func testHeadAndTailMoovPreserveMediaAndTrackOffsets() async throws {
        let f = MP4Fixtures.self
        let metadata = MovieMetadata(from: try f.model())
        let movie = f.box("moov", f.track)
        for input in [f.ftyp + movie + f.box("mdat", f.media), f.ftyp + f.box("mdat", f.media) + movie] {
            let before = try f.atoms(input).first { $0.type == "mdat" }!
            let output = try await write(input, metadata: metadata)
            let boxes = try f.atoms(output)
            XCTAssertEqual(boxes.filter { $0.type == "moov" }.count, 1)
            let after = boxes.first { $0.type == "mdat" }!
            XCTAssertEqual(after.offset, before.offset)
            XCTAssertEqual(after.body, f.media)
            let moov = boxes.first { $0.type == "moov" }!
            XCTAssertEqual(try f.atoms(moov.body).first { $0.type == "trak" }?.data, f.track)
        }
    }

    @MainActor func testExtendedHeadersAtEveryMetadataLevel() async throws {
        let f = MP4Fixtures.self
        let old = f.box("ilst", f.text("©too", "existing encoder"), extended: true)
        let meta = f.box("meta", Data(count: 4) + old, extended: true)
        let moov = f.box("moov", f.track + f.box("udta", meta, extended: true), extended: true)
        let output = try await write(f.ftyp + f.box("mdat", f.media, extended: true) + moov,
                                     metadata: MovieMetadata(from: try f.model()))
        let children = try f.atoms(f.atoms(output).first { $0.type == "moov" }!.body)
        XCTAssertEqual(children.first { $0.type == "trak" }?.data, f.track)
        XCTAssertTrue(try f.ilst(output).contains { $0.data == f.text("©too", "existing encoder") })
    }

    @MainActor func testOpenEndedMediaGetsFiniteSizeBeforeAppendingMoov() async throws {
        let f = MP4Fixtures.self
        let input = f.ftyp + f.box("moov", f.track) + f.box("mdat", f.media, eof: true)
        let output = try await write(input, metadata: MovieMetadata(from: try f.model()))
        let boxes = try f.atoms(output)
        XCTAssertEqual(boxes.map(\.type), ["ftyp", "free", "mdat", "moov"])
        XCTAssertEqual(boxes.first { $0.type == "mdat" }?.body, f.media)
    }

    @MainActor func testOpenEndedChildDoesNotSwallowNewMetadata() async throws {
        let f = MP4Fixtures.self
        let moov = f.box("moov", f.box("trak", Data("track".utf8), eof: true))
        let output = try await write(f.ftyp + f.box("mdat", f.media) + moov, metadata: MovieMetadata(from: try f.model()))
        let result = try f.atoms(output).first { $0.type == "moov" }!
        XCTAssertEqual(try f.atoms(result.body).map(\.type), ["trak", "udta"])
    }

    @MainActor func testUnrelatedTagsAndArtworkSurviveWhileOwnedTagsAreReplaced() async throws {
        let f = MP4Fixtures.self
        let unknown = f.freeform("other.vendor", "iTunMOVI", value: "keep me")
        let artwork = f.box("covr", Data("existing artwork".utf8))
        let encoder = f.text("©too", "Original encoder")
        let old = f.text("©nam", "Old title") + f.text("©cmt", "Old tagline") + encoder + unknown + artwork
            + f.freeform("com.apple.iTunes", "iTunMOVI", value: "old cast")
        let moov = f.box("moov", f.track + f.box("udta", f.box("meta", Data(count: 4) + f.box("ilst", old))))
        let output = try await write(f.ftyp + f.box("mdat", f.media) + moov, metadata: MovieMetadata(from: try f.model()))
        let items = try f.ilst(output)
        for preserved in [encoder, unknown, artwork] { XCTAssertTrue(items.contains { $0.data == preserved }) }
        XCTAssertEqual(items.filter { $0.type == "©nam" }.count, 1)
        XCTAssertFalse(items.contains { $0.type == "©cmt" })
        XCTAssertNil(output.range(of: Data("old cast".utf8)))
    }

    @MainActor func testEditedYearAndJSONAgreeWithoutInventingMonthAndDay() async throws {
        let f = MP4Fixtures.self
        let model = try f.model()
        XCTAssertEqual(MovieMetadata(from: model).releaseDate, "1994-09-23")
        model.year = "2000"
        let snapshot = MovieMetadata(from: model)
        model.year = "2026"
        XCTAssertEqual(snapshot.year, "2000")
        XCTAssertEqual(snapshot.releaseDate, "2000")
        let output = try await write(f.ftyp + f.box("mdat", f.media) + f.box("moov", f.track), metadata: snapshot)
        XCTAssertTrue(try f.ilst(output).contains { $0.data == f.text("©day", "2000") })
        XCTAssertNotNil(output.range(of: Data(#""release_date":"2000""#.utf8)))
        model.year = ""
        XCTAssertEqual(MovieMetadata(from: model).releaseDate, "")
    }

    @MainActor func testMalformedAndUnsupportedFilesLeaveOriginalUnchanged() async throws {
        let f = MP4Fixtures.self
        let validPrefix = f.ftyp + f.box("mdat", f.media)
        var inputs: [Data] = []
        inputs.append(validPrefix + f.box("moov", f.uint32(1000) + Data("trak".utf8)))
        inputs.append(validPrefix + f.box("moov", f.box("udta", f.box("meta"))))
        let hugeHeader = f.uint32(1) + Data("moov".utf8) + f.uint64(UInt64.max)
        inputs.append(validPrefix + hugeHeader)
        inputs.append(validPrefix + f.box("moov", f.track) + Data([0, 0]))
        inputs.append(validPrefix + f.box("moov", f.track + f.box("mvex")))
        inputs.append(validPrefix + f.box("moov", f.track) + f.box("moov", f.track))
        inputs.append(validPrefix + f.uint32(1) + Data("moov".utf8))
        let metadata = MovieMetadata(from: try f.model())
        for (index, input) in inputs.enumerated() {
            let url = directory.appendingPathComponent("bad-\(index).mp4")
            try input.write(to: url)
            do {
                try await MetadataWriter().writeMetadata(fileURL: url, metadata: metadata, progressHandler: { _ in })
                XCTFail("Expected rejection for fixture \(index)")
            } catch {
                XCTAssertEqual(try Data(contentsOf: url), input)
            }
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".movietagger-") })
    }

    @MainActor func testRepeatedWritesDoNotAccumulateMoovOrMetadataAtoms() async throws {
        let f = MP4Fixtures.self
        let metadata = MovieMetadata(from: try f.model())
        let first = try await write(f.ftyp + f.box("moov", f.track) + f.box("mdat", f.media), metadata: metadata)
        let second = try await write(first, metadata: metadata)
        XCTAssertEqual(try f.atoms(second).filter { $0.type == "moov" }.count, 1)
        XCTAssertEqual(try f.ilst(second).filter { $0.type == "©nam" }.count, 1)
        XCTAssertEqual(first.count, second.count)
    }
}
