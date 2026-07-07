import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdateManager

    var body: some View {
        Group {
            if appState.apiKey.isEmpty {
                apiKeyPromptView
            } else {
                mainContent
            }
        }
        // Window title always says which file is being worked on mid-flow.
        .navigationSubtitle(appState.selectedFileURL?.lastPathComponent ?? "")
        .alert("Error", isPresented: $appState.showError) {
            if appState.errorIsAuthFailure {
                OpenSettingsAlertButton()
            }
            Button("OK", role: .cancel) { appState.showError = false }
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $updater.showUpdatePrompt) {
            if let release = updater.availableRelease {
                UpdatePromptView(release: release)
                    .environmentObject(updater)
            }
        }
        // Feedback for the menu-initiated check (Settings has its own status line).
        .alert("You\u{2019}re up to date", isPresented: upToDateAlertBinding) {
            Button("OK") { updater.phase = .idle }
        } message: {
            Text("MovieTagger \(updater.currentVersionString) is the latest version.")
        }
        .alert("Update Check Failed", isPresented: checkFailedAlertBinding) {
            Button("OK") { updater.phase = .idle }
        } message: {
            Text(checkFailureMessage)
        }
        .task {
            // Give launch a moment before phoning home.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await updater.checkAutomatically()
        }
    }

    private var upToDateAlertBinding: Binding<Bool> {
        Binding(
            get: { updater.phase == .upToDate },
            set: { if !$0 { updater.phase = .idle } }
        )
    }

    private var checkFailedAlertBinding: Binding<Bool> {
        Binding(
            get: {
                // Failures during an update are shown inside the sheet instead.
                if case .failed = updater.phase, !updater.showUpdatePrompt { return true }
                return false
            },
            set: { if !$0 { updater.phase = .idle } }
        )
    }

    private var checkFailureMessage: String {
        if case .failed(let message) = updater.phase { return message }
        return ""
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.currentScreen {
        case .fileSelection:
            FileSelectionView()
        case .movieSearch:
            MovieSearchView()
        case .reviewEdit:
            ReviewEditView()
        case .progress:
            ProgressResultView()
        }
    }

    private var apiKeyPromptView: some View {
        ApiKeyPromptView()
    }
}

/// "Open Settings" that actually works inside alert actions on every OS:
/// AppKit blocks the showSettingsWindow: selector from Sonoma on, and
/// SettingsLink can't be used in alerts — but the openSettings environment
/// action can.
private struct OpenSettingsAlertButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            ModernOpenSettingsButton()
        } else {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

@available(macOS 14, *)
private struct ModernOpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Settings") { openSettings() }
    }
}

private struct ApiKeyPromptView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("TMDb API Key Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("To search for movies, you need a TMDb API key.\nGet one for free at themoviedb.org.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if #available(macOS 14, *) {
                SettingsLink {
                    Text("Open Settings")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
