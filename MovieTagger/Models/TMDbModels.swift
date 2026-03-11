import Foundation

// MARK: - Configuration

struct TMDbConfiguration: Codable {
    let images: ImageConfig

    struct ImageConfig: Codable {
        let secureBaseUrl: String
        let posterSizes: [String]

        enum CodingKeys: String, CodingKey {
            case secureBaseUrl = "secure_base_url"
            case posterSizes   = "poster_sizes"
        }
    }
}

// MARK: - Search

struct TMDbSearchResponse: Codable {
    let page: Int
    let results: [TMDbSearchResult]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages   = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDbSearchResult: Codable, Identifiable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let releaseDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, popularity
        case originalTitle = "original_title"
        case releaseDate   = "release_date"
        case posterPath    = "poster_path"
        case voteAverage   = "vote_average"
    }

    var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

// MARK: - Movie Details

struct TMDbMovieDetails: Codable {
    let id: Int
    let title: String
    let originalTitle: String?
    let originalLanguage: String?
    let overview: String?
    let tagline: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [TMDbGenre]?
    let posterPath: String?
    let imdbId: String?
    let voteAverage: Double?
    let voteCount: Int?
    let productionCompanies: [TMDbProductionCompany]?
    let credits: TMDbCredits?
    let releaseDates: TMDbReleaseDatesResponse?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, tagline, runtime, genres, credits
        case originalTitle       = "original_title"
        case originalLanguage    = "original_language"
        case releaseDate         = "release_date"
        case posterPath          = "poster_path"
        case imdbId              = "imdb_id"
        case voteAverage         = "vote_average"
        case voteCount           = "vote_count"
        case productionCompanies = "production_companies"
        case releaseDates        = "release_dates"
    }

    var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

struct TMDbGenre: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TMDbProductionCompany: Codable {
    let id: Int
    let name: String
}

// MARK: - Credits

struct TMDbCredits: Codable {
    let cast: [TMDbCastMember]?
    let crew: [TMDbCrewMember]?
}

struct TMDbCastMember: Codable {
    let id: Int
    let name: String
    let character: String?
    let order: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
    }
}

struct TMDbCrewMember: Codable {
    let id: Int
    let name: String
    let job: String?
    let department: String?

    enum CodingKeys: String, CodingKey {
        case id, name, job, department
    }
}

// MARK: - Release Dates

struct TMDbReleaseDatesResponse: Codable {
    let results: [TMDbReleaseDateCountry]?
}

struct TMDbReleaseDateCountry: Codable {
    let iso3166_1: String
    let releaseDates: [TMDbReleaseDate]?

    enum CodingKeys: String, CodingKey {
        case iso3166_1  = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct TMDbReleaseDate: Codable {
    let certification: String?
    let type: Int?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case certification, type
        case releaseDate = "release_date"
    }
}

// MARK: - Images

struct TMDbImagesResponse: Codable {
    let posters: [TMDbImage]?
}

struct TMDbImage: Codable, Identifiable {
    let filePath: String
    let width: Int
    let height: Int
    let iso639_1: String?
    let voteAverage: Double?

    var id: String { filePath }

    enum CodingKeys: String, CodingKey {
        case width, height
        case filePath     = "file_path"
        case iso639_1     = "iso_639_1"
        case voteAverage  = "vote_average"
    }
}
