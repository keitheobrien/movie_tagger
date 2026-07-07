import SwiftUI

/// Sheet offering an available update: release notes, then download/install
/// progress. Presented from ContentView whenever UpdateManager finds a newer
/// release.
struct UpdatePromptView: View {
    @EnvironmentObject var updater: UpdateManager
    let release: GitHubRelease

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("MovieTagger \(versionLabel) is available \u{2014} you have \(updater.currentVersionString).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .frame(height: 220)

            Divider()

            footer
                .padding()
        }
        .frame(width: 480)
        // Escape must never silently detach the UI from a running update:
        // downloads are cancelled via the Cancel button; installation is the
        // point of no return.
        .interactiveDismissDisabled(updater.isBusy)
    }

    private var versionLabel: String {
        release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
    }

    private var notes: AttributedString {
        let body = release.body ?? "No release notes."
        return (try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(body)
    }

    @ViewBuilder
    private var footer: some View {
        switch updater.phase {
        case .downloading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                HStack {
                    Text("Downloading\u{2026} \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { updater.cancelUpdate() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Downloading update, \(Int((updaterProgress) * 100)) percent")

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing\u{2026} the app will relaunch automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Installing update")

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                HStack {
                    Link("Open Releases Page", destination: releasesURL)
                        .font(.caption)
                    Spacer()
                    Button("Close") { dismissPrompt() }
                        .keyboardShortcut(.cancelAction)
                }
            }

        default:
            HStack {
                Link("View on GitHub", destination: releasesURL)
                    .font(.caption)
                Spacer()
                Button("Later") { dismissPrompt() }
                    .keyboardShortcut(.cancelAction)
                Button("Update Now") { updater.performUpdate(release) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var updaterProgress: Double {
        if case .downloading(let p) = updater.phase { return p }
        return 0
    }

    private var releasesURL: URL {
        URL(string: release.htmlUrl) ?? URL(string: "https://github.com/\(UpdateManager.repo)/releases")!
    }

    private func dismissPrompt() {
        // Keep availableRelease: the sheet content stays valid through the
        // dismissal animation, and Settings keeps showing "vX is available".
        updater.showUpdatePrompt = false
        if case .failed = updater.phase { updater.phase = .idle }
    }
}
