import Foundation

/// Immutable input captured on the main actor before any file work begins.
struct MovieMetadata: Sendable {
    let title: String
    let year: String
    let overview: String
    let tagline: String
    let runtime: String
    let originalTitle: String
    let originalLanguage: String
    let releaseDate: String
    let voteAverage: String
    let studio: String
    let contentRating: String
    let tmdbId: String
    let imdbId: String
    let namingPattern: String
    let genres: [String]
    let cast: [String]
    let directors: [String]
    let screenwriters: [String]
    let producers: [String]
    let resolution: VideoResolution
    let posterImageData: Data?
    let rawDetailsJSON: Data?
    let posterURL: String?
    let renameFile: Bool

    @MainActor
    init(from model: MovieEditModel) {
        title = model.title
        year = model.year
        overview = model.overview
        tagline = model.tagline
        runtime = model.runtime
        originalTitle = model.originalTitle
        originalLanguage = model.originalLanguage
        voteAverage = model.voteAverage
        studio = model.studio
        contentRating = model.contentRating
        tmdbId = model.tmdbId
        imdbId = model.imdbId
        namingPattern = model.namingPattern
        genres = model.genres
        cast = model.cast
        directors = model.directors
        screenwriters = model.screenwriters
        producers = model.producers
        resolution = model.resolution
        posterImageData = model.posterImageData
        rawDetailsJSON = model.rawDetailsJSON
        posterURL = model.posterURL
        renameFile = model.renameFile
        // Keep the full date only while its year still matches the user's edit.
        // An edited year has no known month/day; don't invent them.
        releaseDate = model.year == String(model.releaseDate.prefix(4))
            ? model.releaseDate : model.year
    }
}
