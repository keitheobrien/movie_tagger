import Foundation
import AppKit

// MARK: - Video Resolution

enum VideoResolution: String, CaseIterable, Identifiable {
    case sd480   = "SD 480P"
    case hd720   = "HD 720P"
    case hd1080  = "HD 1080P"
    case hd2160  = "HD 2160P"

    var id: String { rawValue }

    /// The iTunes `hdvd` atom value: 0=SD, 1=720p, 2=1080p, 3=4K
    var hdvdValue: UInt8 {
        switch self {
        case .sd480:  return 0
        case .hd720:  return 1
        case .hd1080: return 2
        case .hd2160: return 3
        }
    }

    /// Auto-detect from video height in pixels.
    static func detect(from height: Int) -> VideoResolution {
        if height >= 2000 { return .hd2160 }
        if height >= 1000 { return .hd1080 }
        if height >= 700  { return .hd720 }
        return .sd480
    }
}

/// User-editable model bridging TMDb data and the metadata writer.
class MovieEditModel: ObservableObject {
    // Core fields
    @Published var title: String
    @Published var year: String
    @Published var overview: String
    @Published var tagline: String
    @Published var genres: [String]
    @Published var runtime: String
    @Published var originalTitle: String
    @Published var originalLanguage: String
    @Published var releaseDate: String
    @Published var voteAverage: String

    // Cast & Crew
    @Published var cast: [String]
    @Published var directors: [String]
    @Published var screenwriters: [String]
    @Published var producers: [String]
    @Published var studio: String
    @Published var contentRating: String
    @Published var resolution: VideoResolution = .hd1080

    // IDs (read-only in UI)
    @Published var tmdbId: String
    @Published var imdbId: String

    // Poster
    @Published var posterImageData: Data?
    @Published var posterURL: String?
    @Published var availablePosters: [TMDbImage] = []
    @Published var selectedPosterPath: String?

    // File naming
    @Published var renameFile: Bool = true
    @Published var namingPattern: String = "{title} ({year})"

    // Raw JSON for custom metadata payload
    var rawDetailsJSON: Data?

    init(from details: TMDbMovieDetails) {
        self.title            = details.title
        self.year             = details.year ?? ""
        self.overview         = details.overview ?? ""
        self.tagline          = details.tagline ?? ""
        self.genres           = details.genres?.map(\.name) ?? []
        self.runtime          = details.runtime.map { String($0) } ?? ""
        self.originalTitle    = details.originalTitle ?? ""
        self.originalLanguage = details.originalLanguage ?? ""
        self.releaseDate      = details.releaseDate ?? ""
        self.voteAverage      = details.voteAverage.map { String(format: "%.1f", $0) } ?? ""
        self.tmdbId           = String(details.id)
        self.imdbId           = details.imdbId ?? ""
        self.selectedPosterPath = details.posterPath

        // Cast (top 10 billed)
        self.cast = (details.credits?.cast ?? [])
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            .prefix(10)
            .map(\.name)

        // Directors
        self.directors = (details.credits?.crew ?? [])
            .filter { $0.job == "Director" }
            .map(\.name)

        // Screenwriters (Writing department)
        self.screenwriters = (details.credits?.crew ?? [])
            .filter { $0.department == "Writing" }
            .map(\.name)

        // Producers
        self.producers = (details.credits?.crew ?? [])
            .filter { $0.job == "Producer" }
            .map(\.name)

        // Studio (first production company)
        self.studio = details.productionCompanies?.first?.name ?? ""

        // Content rating (US certification)
        self.contentRating = Self.extractUSRating(from: details)
    }

    /// Extract the US MPAA rating from TMDb release_dates data.
    private static func extractUSRating(from details: TMDbMovieDetails) -> String {
        guard let countries = details.releaseDates?.results else { return "" }
        guard let us = countries.first(where: { $0.iso3166_1 == "US" }) else { return "" }
        // Prefer theatrical (type 3) certification, fall back to any non-empty
        if let theatrical = us.releaseDates?.first(where: { $0.type == 3 }),
           let cert = theatrical.certification, !cert.isEmpty {
            return cert
        }
        return us.releaseDates?.compactMap(\.certification).first(where: { !$0.isEmpty }) ?? ""
    }
}
