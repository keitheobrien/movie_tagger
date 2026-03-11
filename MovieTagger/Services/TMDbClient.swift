import Foundation

actor TMDbClient {
    private let baseURL = "https://api.themoviedb.org/3"
    private let session: URLSession
    private var apiKey: String
    private var cachedConfig: TMDbConfiguration?
    private var configCacheDate: Date?

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func updateApiKey(_ key: String) {
        self.apiKey = key
        self.cachedConfig = nil
    }

    // MARK: - Public API

    func searchMovies(query: String, language: String = "en-US", page: Int = 1) async throws -> TMDbSearchResponse {
        var components = URLComponents(string: "\(baseURL)/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "query",    value: query),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page",     value: String(page))
        ]
        return try await request(url: components.url!)
    }

    func fetchMovieDetails(id: Int, language: String = "en-US") async throws -> TMDbMovieDetails {
        var components = URLComponents(string: "\(baseURL)/movie/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "credits,release_dates")
        ]
        return try await request(url: components.url!)
    }

    func fetchConfiguration() async throws -> TMDbConfiguration {
        if let cached = cachedConfig,
           let date = configCacheDate,
           Date().timeIntervalSince(date) < 86_400 {
            return cached
        }
        var components = URLComponents(string: "\(baseURL)/configuration")!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        let config: TMDbConfiguration = try await request(url: components.url!)
        cachedConfig = config
        configCacheDate = Date()
        return config
    }

    func fetchMovieImages(id: Int, language: String? = "en") async throws -> TMDbImagesResponse {
        var components = URLComponents(string: "\(baseURL)/movie/\(id)/images")!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        if let lang = language {
            items.append(URLQueryItem(name: "include_image_language", value: "\(lang),null"))
        }
        components.queryItems = items
        return try await request(url: components.url!)
    }

    func fetchImageData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw TMDbError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func posterURL(path: String, size: String = "original") async throws -> URL {
        let config = try await fetchConfiguration()
        let base = config.images.secureBaseUrl
        guard let url = URL(string: "\(base)\(size)\(path)") else {
            throw TMDbError.invalidURL
        }
        return url
    }

    // MARK: - Fetch details + raw JSON together

    func fetchMovieDetailsWithRawJSON(id: Int, language: String = "en-US") async throws -> (TMDbMovieDetails, Data) {
        var components = URLComponents(string: "\(baseURL)/movie/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "credits,release_dates")
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validateHTTPResponse(response)
        let details = try JSONDecoder().decode(TMDbMovieDetails.self, from: data)
        return (details, data)
    }

    // MARK: - Private

    private func request<T: Decodable>(url: URL, retryCount: Int = 0) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw TMDbError.unauthorized
        case 404:
            throw TMDbError.notFound
        case 429:
            if retryCount < 3 {
                let delay = pow(2.0, Double(retryCount))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await request(url: url, retryCount: retryCount + 1)
            }
            throw TMDbError.rateLimited
        default:
            throw TMDbError.httpError(http.statusCode)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw TMDbError.unauthorized
        case 404: throw TMDbError.notFound
        case 429: throw TMDbError.rateLimited
        default:  throw TMDbError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum TMDbError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "Invalid URL."
        case .invalidResponse: return "Invalid response from server."
        case .unauthorized:    return "Invalid API key. Please update your TMDb API key in Settings."
        case .notFound:        return "Movie not found."
        case .rateLimited:     return "Too many requests. Please try again later."
        case .httpError(let c): return "HTTP error \(c)."
        }
    }
}
