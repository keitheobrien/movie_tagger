import Foundation
import Combine

struct MetadataWriteResult: Sendable {
    let url: URL
    let renameWarning: String?
}

/// Owns an operation independently of the lifetime of any SwiftUI screen.
@MainActor
final class MetadataWriteCoordinator: ObservableObject {
    typealias Operation = @Sendable (URL, MovieMetadata, @escaping @Sendable (Float) -> Void) async throws -> MetadataWriteResult

    @Published private(set) var isWriting = false
    @Published private(set) var progress: Float = 0
    @Published private(set) var result: MetadataWriteResult?
    @Published private(set) var errorMessage: String?
    private let operation: Operation
    private var operationID = UUID()

    init(operation: @escaping Operation = { url, metadata, progress in
        try await MetadataWriteOperation.run(url, metadata, progress)
    }) {
        self.operation = operation
    }

    @discardableResult
    func start(fileURL: URL, metadata: MovieMetadata,
               completion: @escaping @MainActor (MetadataWriteResult) -> Void = { _ in }) -> Bool {
        guard !isWriting else { return false }
        // Set synchronously, before the first suspension or navigation event.
        isWriting = true
        progress = 0
        result = nil
        errorMessage = nil
        let id = UUID()
        operationID = id
        let reportProgress: @Sendable (Float) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.isWriting, self.operationID == id else { return }
                self.progress = max(self.progress, value)
            }
        }
        Task {
            defer { isWriting = false }
            do {
                let output = try await operation(fileURL, metadata, reportProgress)
                progress = 1
                result = output
                completion(output)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    func reset() {
        guard !isWriting else { return }
        progress = 0
        result = nil
        errorMessage = nil
    }
}

enum MetadataWriteOperation {
    private static let renameQueue = DispatchQueue(label: "com.movietagger.rename-io", qos: .userInitiated)

    static func run(_ url: URL, _ metadata: MovieMetadata,
                    _ progress: @escaping @Sendable (Float) -> Void) async throws -> MetadataWriteResult {
        try await MetadataWriter().writeMetadata(fileURL: url, metadata: metadata, progressHandler: progress)
        return await withCheckedContinuation { continuation in
            renameQueue.async {
                let formatter = FilenameFormatter()
                guard metadata.renameFile,
                      let name = formatter.formatIfValid(pattern: metadata.namingPattern, model: metadata) else {
                    continuation.resume(returning: MetadataWriteResult(url: url, renameWarning: nil))
                    return
                }
                let target = formatter.resolveCollision(directoryURL: url.deletingLastPathComponent(),
                                                        desiredName: name, excluding: url)
                do {
                    if target.standardizedFileURL.path != url.standardizedFileURL.path {
                        try FileManager.default.moveItem(at: url, to: target)
                    }
                    continuation.resume(returning: MetadataWriteResult(url: target, renameWarning: nil))
                } catch {
                    continuation.resume(returning: MetadataWriteResult(url: url,
                        renameWarning: "Metadata was written, but the file could not be renamed: \(error.localizedDescription)"))
                }
            }
        }
    }
}
