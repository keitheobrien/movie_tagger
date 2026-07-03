import SwiftUI

struct ProgressResultView: View {
    @EnvironmentObject var appState: AppState
    @State private var progress: Float = 0
    @State private var isComplete = false
    @State private var outputURL: URL?
    @State private var errorMessage: String?

    private let writer = MetadataWriter()
    private let formatter = FilenameFormatter()

    var body: some View {
        VStack(spacing: 24) {
            if let err = errorMessage {
                errorView(err)
            } else if isComplete, let url = outputURL {
                successView(url)
            } else {
                progressView
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startWriting() }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(progress))
                .progressViewStyle(.linear)
                .frame(width: 300)

            Text("Writing metadata\u{2026}")
                .foregroundColor(.secondary)

            Text("\(Int(progress * 100))%")
                .font(.title3)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    // MARK: - Success

    private func successView(_ url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Metadata Written Successfully")
                .font(.title2)
                .fontWeight(.semibold)

            Text(url.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)

                Button("Open File") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)

                Button("Tag Another") { appState.reset() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Metadata Write Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Try Again") {
                    errorMessage = nil
                    progress = 0
                    startWriting()
                }
                .buttonStyle(.borderedProminent)

                Button("Go Back") { appState.currentScreen = .reviewEdit }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Write logic (in-place, no temp file, no remux, no copy)

    private func startWriting() {
        guard let inputURL = appState.selectedFileURL,
              let model = appState.movieEditModel else {
            errorMessage = "Missing file or movie data."
            return
        }

        Task {
            do {
                // Step 1: Write metadata in-place (edits moov atom only, sub-second)
                try await writer.writeMetadata(
                    fileURL: inputURL,
                    model: model,
                    progressHandler: { @MainActor p in self.progress = p }
                )

                // Step 2: Rename if requested (instant move, no data copied).
                // formatIfValid returns nil for an empty/invalid pattern — skip the
                // rename rather than produce an invisible ".mp4" dotfile.
                var finalURL = inputURL
                if model.renameFile,
                   let desiredName = formatter.formatIfValid(pattern: model.namingPattern, model: model) {
                    let directory = inputURL.deletingLastPathComponent()
                    let targetURL = formatter.resolveCollision(
                        directoryURL: directory, desiredName: desiredName, excluding: inputURL
                    )

                    if targetURL.standardizedFileURL.path != inputURL.standardizedFileURL.path {
                        do {
                            try FileManager.default.moveItem(at: inputURL, to: targetURL)
                            finalURL = targetURL
                        } catch {
                            // Metadata was already written successfully — report the
                            // rename failure as exactly that, not as a write failure.
                            await MainActor.run {
                                outputURL = inputURL
                                isComplete = true
                                appState.showError(
                                    "Metadata was written, but the file could not be renamed: \(error.localizedDescription)"
                                )
                            }
                            return
                        }
                    }
                }

                await MainActor.run {
                    outputURL = finalURL
                    isComplete = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
