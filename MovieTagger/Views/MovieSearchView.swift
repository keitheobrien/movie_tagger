import SwiftUI

struct MovieSearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSearching = false
    @State private var isLoadingDetails = false
    @State private var selectedResultID: Int?
    @State private var detailsTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Find Movie")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack {
                    TextField("Movie name\u{2026}", text: $appState.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFieldFocused)
                        .onSubmit { performSearch() }

                    Button("Search") { performSearch() }
                        .disabled(appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
            }
            .padding()

            Divider()

            // Results: native list — single click selects, double-click or
            // Return/Choose opens, arrow keys navigate.
            if isSearching || isLoadingDetails {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView(isLoadingDetails ? "Loading movie details\u{2026}" : "Searching\u{2026}")
                    if isLoadingDetails {
                        Button("Cancel") { cancelDetailsLoad() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                Spacer()
            } else if appState.searchResults.isEmpty && appState.hasSearched {
                Spacer()
                VStack(spacing: 8) {
                    Text("No results found.")
                        .foregroundColor(.secondary)
                    Text("Try different search terms, or check the spelling of the title.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(selection: $selectedResultID) {
                    ForEach(appState.searchResults) { result in
                        SearchResultRow(result: result)
                            .tag(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { selectMovie(result) }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Back") {
                    cancelDetailsLoad()
                    appState.currentScreen = .fileSelection
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Choose") {
                    if let id = selectedResultID,
                       let result = appState.searchResults.first(where: { $0.id == id }) {
                        selectMovie(result)
                    }
                }
                .buttonStyle(.borderedProminent)
                // While the search field is focused, Return means "search" —
                // don't let the default action steal it for a stale selection.
                .keyboardShortcut(searchFieldFocused ? nil : .defaultAction)
                .disabled(selectedResultID == nil || isLoadingDetails || isSearching)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !appState.searchQuery.isEmpty && !appState.hasSearched {
                performSearch()
            }
            DispatchQueue.main.async { searchFieldFocused = true }
        }
    }

    // MARK: - Search

    private func performSearch() {
        guard let client = appState.tmdbClient else {
            appState.showError("TMDb client not configured. Set your API key in Settings.")
            return
        }
        let query = appState.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isSearching else { return }

        isSearching = true

        Task {
            do {
                let response = try await client.searchMovies(query: query, language: appState.language)
                await MainActor.run {
                    // Ignore a slow response for a query the user has since changed.
                    guard appState.searchQuery.trimmingCharacters(in: .whitespaces) == query else {
                        isSearching = false
                        return
                    }
                    appState.searchResults = response.results
                    // Only claim "No results found" for searches that actually
                    // completed — a failed search keeps its previous state.
                    appState.hasSearched = true
                    selectedResultID = nil
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    appState.showError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Select movie

    private func cancelDetailsLoad() {
        detailsTask?.cancel()
        detailsTask = nil
        isLoadingDetails = false
    }

    private func selectMovie(_ result: TMDbSearchResult) {
        // Re-selecting the movie already being edited (e.g. after pressing Back):
        // return to the existing edit session instead of rebuilding the model,
        // so the user's edits survive the round trip.
        if let existing = appState.movieEditModel, existing.tmdbId == String(result.id) {
            appState.currentScreen = .reviewEdit
            return
        }

        guard let client = appState.tmdbClient else { return }
        isLoadingDetails = true

        detailsTask = Task {
            do {
                let (details, rawJSON) = try await client.fetchMovieDetailsWithRawJSON(
                    id: result.id, language: appState.language
                )

                let navigatedModel = await MainActor.run { () -> MovieEditModel? in
                    isLoadingDetails = false
                    // The user may have pressed Back (or Cancel) while we were
                    // loading — never yank them forward to a screen they left.
                    guard !Task.isCancelled, appState.currentScreen == .movieSearch else {
                        return nil
                    }
                    let editModel = MovieEditModel(from: details)
                    editModel.namingPattern = appState.defaultNamingPattern
                    editModel.rawDetailsJSON = rawJSON
                    editModel.resolution = appState.detectedResolution
                    appState.selectedDetails = details
                    appState.movieEditModel = editModel
                    appState.currentScreen = .reviewEdit
                    return editModel
                }
                guard let editModel = navigatedModel else { return }

                // Posters load in their own task so leaving the search screen
                // (which is expected — we just navigated) doesn't cancel them.
                // The task writes to the exact model it was started for — never
                // to "whatever model is current when the download finishes".
                Task { await fetchPosters(for: details, into: editModel, title: result.title, client: client) }
            } catch is CancellationError {
                await MainActor.run { isLoadingDetails = false }
            } catch let error as URLError where error.code == .cancelled {
                await MainActor.run { isLoadingDetails = false }
            } catch {
                await MainActor.run {
                    isLoadingDetails = false
                    appState.showError(error.localizedDescription)
                }
            }
        }
    }

    private func fetchPosters(for details: TMDbMovieDetails, into model: MovieEditModel, title: String, client: TMDbClient) async {
        do {
            if let path = details.posterPath {
                let url = try await client.posterURL(path: path)
                let data = try await client.fetchImageData(from: url)
                await MainActor.run {
                    model.posterImageData = data
                    model.posterURL = url.absoluteString
                }
            }

            let images = try await client.fetchMovieImages(id: details.id, language: "en")
            await MainActor.run {
                model.availablePosters = images.posters ?? []
            }
        } catch {
            await MainActor.run {
                // Only bother the user if this movie's session is still active.
                guard appState.movieEditModel === model else { return }
                appState.showError(
                    "Couldn\u{2019}t load posters for \u{201C}\(title)\u{201D}: \(error.localizedDescription) You can retry from the review screen."
                )
            }
        }
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    let result: TMDbSearchResult
    @State private var posterImage: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            posterThumbnail
                .frame(width: 45, height: 67)
                .cornerRadius(4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.title).fontWeight(.medium).lineLimit(1)
                    if let year = result.year {
                        Text("(\(year))").foregroundColor(.secondary)
                    }
                }
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .task { await loadPoster() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// "Title (Year)" plus the first sentence of the overview, so VoiceOver
    /// reads a meaningful summary instead of the raw child views.
    private var accessibilityDescription: String {
        var label = result.title
        if let year = result.year {
            label += " (\(year))"
        }
        if let overview = result.overview,
           let firstSentence = overview.split(separator: ".", omittingEmptySubsequences: true).first {
            label += ". \(firstSentence.trimmingCharacters(in: .whitespaces))."
        }
        return label
    }

    @ViewBuilder
    private var posterThumbnail: some View {
        if let img = posterImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "film").foregroundColor(.gray))
        }
    }

    private func loadPoster() async {
        guard let path = result.posterPath,
              let url = URL(string: "https://image.tmdb.org/t/p/w92\(path)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                await MainActor.run { posterImage = img }
            }
        } catch { }
    }
}
