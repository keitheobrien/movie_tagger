import SwiftUI

struct ProgressResultView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var coordinator: MetadataWriteCoordinator
    private var progress: Float { coordinator.progress }

    var body: some View {
        VStack(spacing: 24) {
            if let err = coordinator.errorMessage {
                errorView(err)
            } else if let result = coordinator.result {
                successView(result.url)
                if let warning = result.renameWarning {
                    Text(warning).foregroundColor(.orange)
                }
            } else {
                progressView
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Writing metadata, \(Int(progress * 100)) percent")
    }

    // MARK: - Success

    private func successView(_ url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
                .accessibilityHidden(true)

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
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
                .accessibilityHidden(true)

            Text("Metadata Write Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Try Again") {
                    appState.startWriting()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Go Back") { appState.currentScreen = .reviewEdit }
                    .buttonStyle(.bordered)
            }
        }
    }

}
