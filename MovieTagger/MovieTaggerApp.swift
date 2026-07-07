import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@main
struct MovieTaggerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        // Single-window app by design: Window (not WindowGroup) removes the
        // File > New Window item, which produced a confusing clone sharing the
        // same wizard state and could even start duplicate concurrent writes.
        Window("MovieTagger", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updateManager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenFileCommand(appState: appState)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updateManager)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updateManager)
        }
    }
}

// MARK: - File > Open command

private struct OpenFileCommand: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open MP4\u{2026}") {
            if appState.chooseFileViaPanel() {
                // Jump to the first screen so the pick is visible no matter
                // where in the wizard the user was, and reopen the main window
                // in case it was closed (the app keeps running without it).
                appState.currentScreen = .fileSelection
                openWindow(id: "main")
            }
        }
        .keyboardShortcut("o")
    }
}

// MARK: - Check for Updates command

private struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdateManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check for Updates\u{2026}") {
            // The prompt sheet lives on the main window — make sure it exists.
            openWindow(id: "main")
            Task { await updater.checkInteractively(origin: .menu) }
        }
        .disabled(updater.phase == .checking || updater.isBusy)
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
    // Duration/resolution summary for the selected file; lives here so it is
    // shared between FileSelectionView and the File > Open menu command.
    @Published var fileInfo = ""
    @Published var detectedResolution: VideoResolution = .hd1080
    @Published var searchQuery = ""
    // Search state lives here (not view-local) so results survive Back/forward
    // navigation instead of being discarded and re-fetched on every visit.
    @Published var searchResults: [TMDbSearchResult] = []
    @Published var hasSearched = false
    @Published var movieEditModel: MovieEditModel?
    @Published var selectedDetails: TMDbMovieDetails?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var errorIsAuthFailure = false

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

    func saveApiKey(_ key: String) throws {
        try KeychainHelper.save(apiKey: key)
        apiKey = key
        tmdbClient = TMDbClient(apiKey: key)
    }

    func removeApiKey() {
        KeychainHelper.delete()
        apiKey = ""
        tmdbClient = nil
    }

    func showError(_ message: String) {
        errorMessage = message
        // Lets the alert offer "Open Settings" when the fix lives there.
        errorIsAuthFailure = message == TMDbError.unauthorized.errorDescription
        showError = true
    }

    func reset() {
        currentScreen = .fileSelection
        selectedFileURL = nil
        fileInfo = ""
        detectedResolution = .hd1080
        searchQuery = ""
        searchResults = []
        hasSearched = false
        movieEditModel = nil
        selectedDetails = nil
    }

    // MARK: - File selection

    /// Shows an open panel and selects the chosen file.
    /// Returns true when the user picked a file rather than cancelling.
    @discardableResult
    func chooseFileViaPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose an MP4 file"
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        selectFile(url)
        return true
    }

    func selectFile(_ url: URL) {
        let isNewFile = selectedFileURL != url

        // A different file invalidates any in-progress edit session and search:
        // the model's resolution and edits are file-specific. (Re-selecting the
        // same file keeps everything, so Back -> re-select preserves edits and a
        // manually refined search query.)
        if isNewFile {
            movieEditModel = nil
            selectedDetails = nil
            searchResults = []
            hasSearched = false
            searchQuery = cleanFilename(url.deletingPathExtension().lastPathComponent)
            detectedResolution = .hd1080
        }
        selectedFileURL = url

        // Basic media info + resolution detection. A file with no readable
        // duration AND no video track isn't a usable MP4 — reject it here
        // instead of letting the problem surface at the final write step.
        let asset = AVURLAsset(url: url)
        Task {
            var info = ""
            var isReadable = false
            if let duration = try? await asset.load(.duration),
               CMTimeGetSeconds(duration).isFinite, CMTimeGetSeconds(duration) > 0 {
                let seconds = CMTimeGetSeconds(duration)
                let m = Int(seconds) / 60
                let s = Int(seconds) % 60
                info = "Duration: \(m)m \(s)s"
                isReadable = true
            }

            // Detect video resolution from the first video track
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let videoTrack = tracks.first,
               let naturalSize = try? await videoTrack.load(.naturalSize) {
                isReadable = true
                let height = Int(naturalSize.height)
                let width = Int(naturalSize.width)
                let detected = VideoResolution.detect(from: height)
                if !info.isEmpty { info += " · " }
                info += "\(width)×\(height) (\(detected.rawValue))"
                await MainActor.run {
                    // Only apply if this file is still the selected one — the
                    // user may have picked another file while we were loading.
                    if self.selectedFileURL == url { self.detectedResolution = detected }
                }
            }

            await MainActor.run {
                guard self.selectedFileURL == url else { return }
                if isReadable {
                    self.fileInfo = info
                } else {
                    self.fileInfo = ""
                    self.selectedFileURL = nil
                    self.showError(
                        "\u{201C}\(url.lastPathComponent)\u{201D} doesn\u{2019}t appear to be a readable MP4 video."
                    )
                }
            }
        }
    }

    private func cleanFilename(_ name: String) -> String {
        var s = name
        let patterns = [
            "\\[.*?\\]",
            "\\(\\d{4}\\)",
            "\\b(720p|1080p|2160p|4K|HDR|BluRay|BRRip|WEB-DL|WEBRip|x264|x265|HEVC|AAC|DTS|REMUX)\\b"
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: ".", with: " ")
        s = s.replacingOccurrences(of: "_", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
