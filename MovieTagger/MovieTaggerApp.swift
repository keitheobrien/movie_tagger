import SwiftUI

@main
struct MovieTaggerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 800, height: 600)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    enum Screen {
        case fileSelection
        case movieSearch
        case reviewEdit
        case progress
    }

    @Published var currentScreen: Screen = .fileSelection
    @Published var selectedFileURL: URL?
    @Published var detectedResolution: VideoResolution = .hd1080
    @Published var searchQuery = ""
    @Published var movieEditModel: MovieEditModel?
    @Published var selectedDetails: TMDbMovieDetails?
    @Published var errorMessage: String?
    @Published var showError = false

    // Settings
    @Published var apiKey = ""
    @Published var language = "en-US"
    @Published var defaultNamingPattern = "{title} ({year})"

    var tmdbClient: TMDbClient?

    init() {
        loadSettings()
    }

    func loadSettings() {
        apiKey = KeychainHelper.load() ?? ""
        language = UserDefaults.standard.string(forKey: "tmdb_language") ?? "en-US"
        defaultNamingPattern = UserDefaults.standard.string(forKey: "naming_pattern") ?? "{title} ({year})"

        if !apiKey.isEmpty {
            tmdbClient = TMDbClient(apiKey: apiKey)
        }
    }

    func saveApiKey(_ key: String) {
        try? KeychainHelper.save(apiKey: key)
        apiKey = key
        tmdbClient = TMDbClient(apiKey: key)
    }

    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func reset() {
        currentScreen = .fileSelection
        selectedFileURL = nil
        detectedResolution = .hd1080
        searchQuery = ""
        movieEditModel = nil
        selectedDetails = nil
    }
}
