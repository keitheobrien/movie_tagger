import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

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
