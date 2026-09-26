import XCTest
import Combine
@testable import MovieTagger

private actor WriteGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

final class MetadataWriteCoordinatorTests: XCTestCase {
    @MainActor func testSingleWriteOwnsSnapshotAndSurvivesNavigation() async throws {
        let started = expectation(description: "operation started")
        let finished = expectation(description: "operation finished")
        let gate = WriteGate()
        let source = URL(fileURLWithPath: "/tmp/input.mp4")
        let output = URL(fileURLWithPath: "/tmp/renamed.mp4")
        let coordinator = MetadataWriteCoordinator { url, metadata, _ in
            XCTAssertEqual(url, source)
            await gate.wait(started: started)
            XCTAssertEqual(metadata.title, "Fixture")
            return MetadataWriteResult(url: output, renameWarning: nil)
        }
        let state = AppState(loadSavedSettings: false, coordinator: coordinator)
        state.selectedFileURL = source
        state.movieEditModel = try MP4Fixtures.model()
        state.startWriting()
        XCTAssertTrue(state.isWritingFile)
        XCTAssertEqual(state.currentScreen, .progress)
        state.movieEditModel?.title = "Changed while working"
        state.selectFile(URL(fileURLWithPath: "/tmp/other.mp4"))
        state.reset()
        state.startWriting()
        XCTAssertEqual(state.selectedFileURL, source)
        XCTAssertEqual(state.currentScreen, .progress)
        // A newly created progress screen simply observes this same coordinator.
        _ = ProgressResultView(coordinator: coordinator)
        XCTAssertFalse(coordinator.start(fileURL: source, metadata: MovieMetadata(from: state.movieEditModel!)))
        await fulfillment(of: [started], timeout: 3)
        let subscription = coordinator.$isWriting.dropFirst().sink { busy in
            if !busy { finished.fulfill() }
        }
        await gate.finish()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(state.selectedFileURL, output)
        XCTAssertEqual(coordinator.result?.url, output)
        XCTAssertFalse(state.isWritingFile)
        withExtendedLifetime(subscription) {}
    }

    @MainActor func testFailedWriteReleasesLockAndCanBeRetried() async throws {
        let coordinator = MetadataWriteCoordinator { _, _, _ in throw POSIXError(.ENOSPC) }
        let state = AppState(loadSavedSettings: false, coordinator: coordinator)
        state.selectedFileURL = URL(fileURLWithPath: "/tmp/input.mp4")
        state.movieEditModel = try MP4Fixtures.model()
        for _ in 0..<2 {
            let finished = expectation(description: "failure delivered")
            let subscription = coordinator.$isWriting.dropFirst().sink { busy in
                if !busy { finished.fulfill() }
            }
            state.startWriting()
            await fulfillment(of: [finished], timeout: 3)
            XCTAssertNotNil(coordinator.errorMessage)
            XCTAssertFalse(coordinator.isWriting)
            XCTAssertNil(coordinator.result)
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor func testUpdateBlocksStartingWrite() throws {
        let state = AppState(loadSavedSettings: false)
        state.selectedFileURL = URL(fileURLWithPath: "/tmp/input.mp4")
        state.movieEditModel = try MP4Fixtures.model()
        state.currentScreen = .reviewEdit
        state.updateIsBusy = { true }
        state.startWriting()
        XCTAssertFalse(state.isWritingFile)
        XCTAssertEqual(state.currentScreen, .reviewEdit)
    }
}
