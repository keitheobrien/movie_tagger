import SwiftUI
import UniformTypeIdentifiers

struct FileSelectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false

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
                        .accessibilityHidden(true)

                    if let url = appState.selectedFileURL {
                        VStack(spacing: 4) {
                            Text(url.lastPathComponent)
                                .fontWeight(.medium)
                            if !appState.fileInfo.isEmpty {
                                Text(appState.fileInfo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Drag & Drop an MP4 or M4V file here")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dropZoneAccessibilityLabel)

            HStack(spacing: 16) {
                Button("Choose MP4\u{2026}") { appState.chooseFileViaPanel() }
                    .buttonStyle(.bordered)

                Button("Next") { appState.currentScreen = .movieSearch }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
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
                    .accessibilityLabel("Settings")
                    .help("Settings")
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
                    .accessibilityLabel("Settings")
                    .help("Settings")
                }
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    private var dropZoneAccessibilityLabel: String {
        if let url = appState.selectedFileURL {
            var label = "Selected file: \(url.lastPathComponent)"
            if !appState.fileInfo.isEmpty {
                label += ", \(appState.fileInfo)"
            }
            return label
        }
        return "Drop zone: drag and drop an MP4 or M4V file here"
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
            DispatchQueue.main.async { appState.selectFile(url) }
        }
        return true
    }
}
