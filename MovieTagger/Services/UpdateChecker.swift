import AppKit
import Foundation
import Security

// MARK: - GitHub release models

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let assets: [Asset]

    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadUrl: String
        let size: Int
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlUrl = "html_url"
    }

    /// The downloadable app zip for this release (e.g. "MovieTagger-1.2.zip").
    var appAsset: Asset? {
        assets.first { $0.name.hasPrefix("MovieTagger") && $0.name.hasSuffix(".zip") }
    }
}

// MARK: - Version comparison

/// Numeric dotted-version comparison ("1.10" > "1.9", tolerates a leading "v").
struct AppVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ string: String) {
        let cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = cleaned.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case noAsset
    case downloadFailed(String)
    case extractionFailed(String)
    case signatureInvalid(String)
    case installLocationNotWritable(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAsset:
            return "The latest release has no downloadable app."
        case .downloadFailed(let m):
            return "Download failed: \(m)"
        case .extractionFailed(let m):
            return "Could not unpack the update: \(m)"
        case .signatureInvalid(let m):
            return "The downloaded update failed signature verification and was discarded: \(m)"
        case .installLocationNotWritable(let path):
            return "The app can\u{2019}t replace itself at \(path). Download the update manually from the releases page."
        case .installFailed(let m):
            return "Could not install the update: \(m)"
        }
    }
}

// MARK: - Update manager

/// Checks the GitHub releases feed, and — with the user's consent — downloads,
/// verifies, installs, and relaunches the latest release.
///
/// Security model: the downloaded bundle is REQUIRED to satisfy
/// "anchor apple generic and certificate leaf[subject.OU] = TEAM_ID" (checked
/// with SecStaticCode against all architectures and nested code) before it is
/// allowed anywhere near the install location. The quarantine attribute is
/// only removed after that check passes. A release that is not newer than the
/// running version is never offered (no downgrades).
@MainActor
final class UpdateManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)   // 0...1
        case installing
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var availableRelease: GitHubRelease?
    @Published var showUpdatePrompt = false

    static let repo = "keitheobrien/movie_tagger"
    static let teamID = "9R236BB67S"
    private static let lastCheckKey = "last_update_check"
    static let autoCheckKey = "auto_update_check"
    private static let checkInterval: TimeInterval = 20 * 60 * 60   // ~daily

    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Checking

    /// Launch-time check: silent unless a newer release is found.
    func checkAutomatically() async {
        guard UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil
                || UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.checkInterval else { return }

        if let release = try? await fetchNewerRelease() {
            availableRelease = release
            showUpdatePrompt = true
        }
        // Errors and "up to date" stay silent on the automatic path.
    }

    /// User-initiated check: everything is surfaced.
    func checkInteractively() async {
        phase = .checking
        do {
            if let release = try await fetchNewerRelease() {
                phase = .idle
                availableRelease = release
                showUpdatePrompt = true
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Returns the latest release only if it is strictly newer than the
    /// running version. MOVIETAGGER_FORCE_UPDATE=1 (testing) skips the
    /// version gate — but never the signature gate.
    private func fetchNewerRelease() async throws -> GitHubRelease? {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed("release feed returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        let force = ProcessInfo.processInfo.environment["MOVIETAGGER_FORCE_UPDATE"] == "1"
        guard let remote = AppVersion(release.tagName),
              let current = AppVersion(currentVersionString) else { return force ? release : nil }
        return (remote > current || force) ? release : nil
    }

    // MARK: Update flow (download -> verify -> install -> relaunch)

    func performUpdate(_ release: GitHubRelease) async {
        do {
            guard let asset = release.appAsset else { throw UpdateError.noAsset }

            phase = .downloading(0)
            let zipURL = try await download(asset)

            phase = .installing
            let newApp = try await Task.detached(priority: .userInitiated) {
                let extracted = try Self.extractApp(from: zipURL)
                try Self.verifyCodeSignature(at: extracted, teamID: Self.teamID)
                Self.removeQuarantine(at: extracted)   // only after verification
                return extracted
            }.value

            let installedURL = try Self.install(newApp: newApp)
            relaunch(at: installedURL)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        guard let url = URL(string: asset.browserDownloadUrl), url.scheme == "https" else {
            throw UpdateError.downloadFailed("invalid asset URL")
        }

        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let expected = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : asset.size
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieTagger-update-\(ProcessInfo.processInfo.processIdentifier).zip")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var received = 0
        var buffer = Data(capacity: 128 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 128 * 1024 {
                try handle.write(contentsOf: buffer)
                received += buffer.count
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    phase = .downloading(min(1, Double(received) / Double(expected)))
                }
            }
        }
        try handle.write(contentsOf: buffer)
        phase = .downloading(1)
        return destination
    }

    private nonisolated static func extractApp(from zipURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieTagger-update-extract-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.extractionFailed("ditto exited with status \(ditto.terminationStatus)")
        }

        let app = dir.appendingPathComponent("MovieTagger.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError.extractionFailed("archive did not contain MovieTagger.app")
        }
        return app
    }

    /// Hard gate: the bundle must be validly signed by THIS team. A tampered,
    /// re-signed, or unsigned download is rejected and deleted.
    private nonisolated static func verifyCodeSignature(at appURL: URL, teamID: String) throws {
        defer {
            // If verification threw, don't leave the suspect bundle around.
        }
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            try? FileManager.default.removeItem(at: appURL)
            throw UpdateError.signatureInvalid("could not read code signature (\(status))")
        }

        var requirement: SecRequirement?
        let req = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        status = SecRequirementCreateWithString(req as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess, let requirement else {
            try? FileManager.default.removeItem(at: appURL)
            throw UpdateError.signatureInvalid("could not compile signing requirement (\(status))")
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            try? FileManager.default.removeItem(at: appURL)
            throw UpdateError.signatureInvalid("bundle is not validly signed by the developer (\(status))")
        }
    }

    /// Safe only after signature verification: the payload has been proven to
    /// come from this developer, which is exactly the assurance quarantine
    /// exists to establish.
    private nonisolated static func removeQuarantine(at url: URL) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    /// Move the running app aside (allowed on macOS — the binary stays mapped)
    /// and move the verified new version into its place. Rolls back on failure.
    private nonisolated static func install(newApp: URL) throws -> URL {
        let fm = FileManager.default
        let currentURL = Bundle.main.bundleURL
        let parent = currentURL.deletingLastPathComponent()

        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.installLocationNotWritable(parent.path)
        }

        // Same-volume staging area so the moves are atomic renames.
        let staging = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: currentURL, create: true
        )
        let backup = staging.appendingPathComponent("MovieTagger-previous.app")

        try fm.moveItem(at: currentURL, to: backup)
        do {
            try fm.moveItem(at: newApp, to: currentURL)
        } catch {
            // Put the old version back; never leave the user with no app.
            try? fm.moveItem(at: backup, to: currentURL)
            throw UpdateError.installFailed(error.localizedDescription)
        }
        try? fm.removeItem(at: backup)
        return currentURL
    }

    private func relaunch(at appURL: URL) {
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        // "$0" keeps the path out of shell-interpretation entirely.
        sh.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", appURL.path]
        try? sh.run()
        NSApp.terminate(nil)
    }
}
