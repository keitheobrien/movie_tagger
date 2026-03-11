import SwiftUI

struct MovieSearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchResults: [TMDbSearchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isLoadingDetails = false

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
                        .onSubmit { performSearch() }

                    Button("Search") { performSearch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
            }
            .padding()

            Divider()

            // Results
            if isSearching || isLoadingDetails {
                Spacer()
                ProgressView(isLoadingDetails ? "Loading movie details\u{2026}" : "Searching\u{2026}")
                Spacer()
            } else if searchResults.isEmpty && hasSearched {
                Spacer()
                Text("No results found.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(searchResults) { result in
                            SearchResultRow(result: result) { selectMovie(result) }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Back") { appState.currentScreen = .fileSelection }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !appState.searchQuery.isEmpty && searchResults.isEmpty {
                performSearch()
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        guard let client = appState.tmdbClient else {
            appState.showError("TMDb client not configured. Set your API key in Settings.")
            return
        }
        let query = appState.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        hasSearched = true

        Task {
            do {
                let response = try await client.searchMovies(query: query, language: appState.language)
                await MainActor.run {
                    searchResults = response.results
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

    private func selectMovie(_ result: TMDbSearchResult) {
        guard let client = appState.tmdbClient else { return }
        isLoadingDetails = true

        Task {
            do {
                let (details, rawJSON) = try await client.fetchMovieDetailsWithRawJSON(
                    id: result.id, language: appState.language
                )

                await MainActor.run {
                    let editModel = MovieEditModel(from: details)
                    editModel.namingPattern = appState.defaultNamingPattern
                    editModel.rawDetailsJSON = rawJSON
                    editModel.resolution = appState.detectedResolution
                    appState.selectedDetails = details
                    appState.movieEditModel = editModel
                    appState.currentScreen = .reviewEdit
                    isLoadingDetails = false
                }

                // Fetch poster in background
                if let path = details.posterPath {
                    let url = try await client.posterURL(path: path)
                    let data = try await client.fetchImageData(from: url)
                    await MainActor.run {
                        appState.movieEditModel?.posterImageData = data
                        appState.movieEditModel?.posterURL = url.absoluteString
                    }
                }

                // Fetch available posters
                let images = try await client.fetchMovieImages(id: result.id, language: "en")
                await MainActor.run {
                    appState.movieEditModel?.availablePosters = images.posters ?? []
                }
            } catch {
                await MainActor.run {
                    isLoadingDetails = false
                    appState.showError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    let result: TMDbSearchResult
    let onSelect: () -> Void
    @State private var posterImage: NSImage?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                posterThumbnail
                    .frame(width: 45, height: 67)
                    .cornerRadius(4)

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

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await loadPoster() }
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
