import XCTest
@testable import MovieTagger

final class AtomicFileUpdateTests: XCTestCase {
    private var directory: URL!
    private var source: URL!
    private let original = Data("Original movie bytes".utf8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("movie.mp4")
        try original.write(to: source)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testDiskFullAfterPartialStagedWriteLeavesSourceUntouched() throws {
        XCTAssertThrowsError(try AtomicFileUpdate.perform(at: source) { staged in
            let handle = try FileHandle(forUpdating: staged)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data("Partial replacement".utf8))
            throw POSIXError(.ENOSPC)
        })
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["movie.mp4"])
    }

    func testOriginalRemainsAvailableUntilSuccessfulCommit() throws {
        let replacement = Data("Complete new bytes".utf8)
        try AtomicFileUpdate.perform(at: source) { staged in
            try replacement.write(to: staged)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["movie.mp4"])
    }

    func testConcurrentSourceModificationIsNotOverwritten() throws {
        let external = Data("External edit with a different length".utf8)
        XCTAssertThrowsError(try AtomicFileUpdate.perform(at: source) { staged in
            try Data("Our edit".utf8).write(to: staged)
            try external.write(to: source)
        })
        XCTAssertEqual(try Data(contentsOf: source), external)
    }

    func testSymlinkStillPointsToUpdatedTarget() throws {
        let link = directory.appendingPathComponent("alias.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let replacement = Data("New movie".utf8)
        try AtomicFileUpdate.perform(at: link) { try replacement.write(to: $0) }
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertEqual(try Data(contentsOf: link), replacement)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
}
