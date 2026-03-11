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
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") { appState.showError = false }
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
