import XCTest
@testable import MovieTagger

final class MetadataWriteOperationTests: XCTestCase {
    private var directory: URL!
    private var source: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("input.mp4")
        let f = MP4Fixtures.self
        try (f.ftyp + f.box("mdat", f.media) + f.box("moov", f.track)).write(to: source)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    @MainActor func testRenameResolvesCollisionWithoutOverwritingExistingMovie() async throws {
        let model = try MP4Fixtures.model()
        model.renameFile = true
        let occupied = directory.appendingPathComponent("Fixture (1994).mp4")
        let otherMovie = Data("Another movie".utf8)
        try otherMovie.write(to: occupied)
        let result = try await MetadataWriteOperation.run(source, MovieMetadata(from: model), { _ in })
        XCTAssertEqual(result.url.lastPathComponent, "Fixture (1994) (1).mp4")
        XCTAssertNil(result.renameWarning)
        XCTAssertEqual(try Data(contentsOf: occupied), otherMovie)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try MP4Fixtures.ilst(Data(contentsOf: result.url)).contains { $0.type == "©nam" })
    }

    @MainActor func testRenameFailureStillReportsSuccessfulMetadataAtOriginalPath() async throws {
        let model = try MP4Fixtures.model()
        model.renameFile = true
        model.namingPattern = String(repeating: "a", count: 300) // exceeds NAME_MAX
        let result = try await MetadataWriteOperation.run(source, MovieMetadata(from: model), { _ in })
        XCTAssertEqual(result.url, source)
        XCTAssertNotNil(result.renameWarning)
        XCTAssertTrue(try MP4Fixtures.ilst(Data(contentsOf: source)).contains { $0.type == "©nam" })
    }

    @MainActor func testEmptyPatternSkipsRenameAndStillWritesMetadata() async throws {
        let model = try MP4Fixtures.model()
        model.renameFile = true
        model.namingPattern = "..."
        let result = try await MetadataWriteOperation.run(source, MovieMetadata(from: model), { _ in })
        XCTAssertEqual(result.url, source)
        XCTAssertNil(result.renameWarning)
        XCTAssertTrue(try MP4Fixtures.ilst(Data(contentsOf: source)).contains { $0.type == "©nam" })
    }
}
