import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct FileSelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var fileInfo = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Movie Metadata Tagger")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select an MP4 file to tag with movie metadata from TMDb")
                .foregroundColor(.secondary)

            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.gray.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragging ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                    .frame(height: 200)

                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    if let url = appState.selectedFileURL {
                        VStack(spacing: 4) {
                            Text(url.lastPathComponent)
                                .fontWeight(.medium)
                            if !fileInfo.isEmpty {
                                Text(fileInfo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Drag & Drop MP4 file here")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }

            HStack(spacing: 16) {
                Button("Choose MP4\u{2026}") { chooseFile() }
                    .buttonStyle(.bordered)

                Button("Next") { appState.currentScreen = .movieSearch }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedFileURL == nil)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            Group {
                if #available(macOS 14, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        // macOS 13 renamed the responder to showSettingsWindow:
                        // (showPreferencesWindow: silently no-ops on Ventura).
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    // MARK: - File picking

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose an MP4 file"
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            selectFile(url)
        }
    }

    private func selectFile(_ url: URL) {
        // A different file invalidates any in-progress edit session: the model's
        // resolution and edits are file-specific. (Re-selecting the same file keeps
        // the session so Back -> re-select same movie preserves edits.)
        if appState.selectedFileURL != url {
            appState.movieEditModel = nil
            appState.selectedDetails = nil
        }
        appState.selectedFileURL = url

        // Basic media info + resolution detection
        let asset = AVURLAsset(url: url)
        Task {
            var info = ""
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                let m = Int(seconds) / 60
                let s = Int(seconds) % 60
                info = "Duration: \(m)m \(s)s"
            }

            // Detect video resolution from the first video track
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let videoTrack = tracks.first,
               let naturalSize = try? await videoTrack.load(.naturalSize) {
                let height = Int(naturalSize.height)
                let width = Int(naturalSize.width)
                let detected = VideoResolution.detect(from: height)
                if !info.isEmpty { info += " · " }
                info += "\(width)×\(height) (\(detected.rawValue))"
                await MainActor.run { appState.detectedResolution = detected }
            }

            await MainActor.run { fileInfo = info }
        }

        // Prefill search query from filename
        appState.searchQuery = cleanFilename(url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "mp4" || ext == "m4v" else {
                DispatchQueue.main.async { appState.showError("Please select an MP4 or M4V file.") }
                return
            }
            DispatchQueue.main.async { selectFile(url) }
        }
        return true
    }

    // MARK: - Filename cleaning

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
