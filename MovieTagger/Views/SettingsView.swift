import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey = ""
    @State private var language = "en-US"
    @State private var namingPattern = "{title} ({year})"
    @State private var isSaved = false

    var body: some View {
        Form {
            Section("TMDb API") {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Text("Get a free API key at themoviedb.org")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Language / Region", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            Section("File Naming") {
                TextField("Default naming pattern", text: $namingPattern)
                    .textFieldStyle(.roundedBorder)

                Text("Tokens: {title}, {year}, {tmdb_id}, {imdb_id}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Attribution") {
                Text("This product uses the TMDb API but is not endorsed or certified by TMDb.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)

                    if isSaved {
                        Text("Saved!")
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding()
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            apiKey = appState.apiKey
            language = appState.language
            namingPattern = appState.defaultNamingPattern
        }
    }

    private func save() {
        appState.saveApiKey(apiKey)

        UserDefaults.standard.set(language, forKey: "tmdb_language")
        appState.language = language

        UserDefaults.standard.set(namingPattern, forKey: "naming_pattern")
        appState.defaultNamingPattern = namingPattern

        withAnimation { isSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isSaved = false }
        }
    }
}
