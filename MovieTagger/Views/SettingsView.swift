import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey = ""
    @State private var language = "en-US"
    @State private var namingPattern = "{title} ({year})"
    @State private var keyStatus: KeyStatus = .idle

    private enum KeyStatus: Equatable {
        case idle
        case verifying
        case saved(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section("TMDb API") {
                HStack {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { verifyAndSaveKey() }

                    Button("Verify & Save") { verifyAndSaveKey() }
                        .disabled(keyStatus == .verifying)
                }

                keyStatusLine

                Text("Get a free API key at themoviedb.org")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Language / Region", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onChange(of: language) { newValue in
                        // Settings apply immediately (macOS convention) — no Save button.
                        appState.language = newValue
                        UserDefaults.standard.set(newValue, forKey: "tmdb_language")
                    }
            }

            Section("File Naming") {
                TextField("Default naming pattern", text: $namingPattern)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: namingPattern) { newValue in
                        appState.defaultNamingPattern = newValue
                        UserDefaults.standard.set(newValue, forKey: "naming_pattern")
                    }

                Text("Tokens: {title}, {year}, {tmdb_id}, {imdb_id}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Attribution") {
                Text("This product uses the TMDb API but is not endorsed or certified by TMDb.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .onDisappear {
            // Never silently drop a pasted key on Cmd+W during onboarding: if the
            // app has NO working key yet, best-effort commit the edit so the user
            // isn't bounced back to the "API Key Required" screen with no
            // explanation. Deliberately narrow: never overwrite an existing key
            // with an unverified edit, never save a v4 token, and never save a
            // key that verification just explicitly failed.
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if appState.apiKey.isEmpty,
               !trimmed.isEmpty,
               !trimmed.hasPrefix("eyJ"),
               !keyStatusIsFailed {
                try? appState.saveApiKey(trimmed)
            }
        }
    }

    private var keyStatusIsFailed: Bool {
        if case .failed = keyStatus { return true }
        return false
    }

    @ViewBuilder
    private var keyStatusLine: some View {
        switch keyStatus {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verifying key with TMDb\u{2026}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .saved(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: - API key verification

    private func verifyAndSaveKey() {
        // onSubmit isn't disabled while verifying — don't start a second pass.
        guard keyStatus != .verifying else { return }

        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed

        guard !trimmed.isEmpty else {
            keyStatus = .failed("API key is empty.")
            return
        }
        // TMDb shows the long v4 "Read Access Token" (a JWT) most prominently;
        // this app needs the short v3 "API Key". Catch the mixup at paste time.
        guard !trimmed.hasPrefix("eyJ") else {
            keyStatus = .failed("That looks like a TMDb v4 Read Access Token. Paste the shorter \u{201C}API Key\u{201D} from your TMDb account settings instead.")
            return
        }

        keyStatus = .verifying
        Task {
            do {
                _ = try await TMDbClient(apiKey: trimmed).fetchConfiguration()
                await MainActor.run { persistVerifiedKey(trimmed) }
            } catch TMDbError.unauthorized {
                await MainActor.run {
                    keyStatus = .failed("TMDb rejected this key. Double-check it and try again.")
                }
            } catch {
                await MainActor.run {
                    keyStatus = .failed("Couldn\u{2019}t verify the key: \(error.localizedDescription)")
                }
            }
        }
    }

    private func persistVerifiedKey(_ key: String) {
        do {
            try appState.saveApiKey(key)
            keyStatus = .saved("Key verified and saved.")
        } catch {
            keyStatus = .failed("Key is valid, but saving it failed: \(error.localizedDescription)")
        }
    }
}
