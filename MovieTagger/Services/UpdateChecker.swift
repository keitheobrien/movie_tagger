import AppKit
import Foundation
import OSLog
import Security

/// Unified-log channel for the updater: `log show --predicate 'subsystem == "com.movietagger.app"'`.
private let log = UpdaterLog()

/// Thin wrapper: unified log always; in DEBUG builds also append to a plain
/// trace file so the flow can be observed end-to-end from a shell.
private struct UpdaterLog {
    private let logger = Logger(subsystem: "com.movietagger.app", category: "updater")
    #if DEBUG
    private let traceURL = FileManager.default.temporaryDirectory.appendingPathComponent("movietagger-updater.log")
    #endif

    func notice(_ message: String) { logger.notice("\(message, privacy: .public)"); trace("NOTICE " + message) }
    func error(_ message: String)  { logger.error("\(message, privacy: .public)");  trace("ERROR  " + message) }

    private func trace(_ line: String) {
        #if DEBUG
        let stamped = "\(Date()) [\(ProcessInfo.processInfo.processIdentifier)] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: traceURL) {
            handle.seekToEndOfFile(); handle.write(Data(stamped.utf8)); try? handle.close()
        } else {
            try? stamped.write(to: traceURL, atomically: true, encoding: .utf8)
        }
        #endif
    }
}

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

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadUrl = "browser_download_url"
        }
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

/// Numeric dotted-version comparison ("1.10" > "1.9", tolerates a leading "v"
/// and pre-release suffixes like "2.0-beta" by parsing the leading numeric core).
struct AppVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ string: String) {
        var cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
        cleaned = String(cleaned.prefix { $0.isNumber || $0 == "." })
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
/// with SecStaticCode against all architectures and nested code, strict
/// validation) before it is allowed anywhere near the install location. The
/// quarantine attribute is only removed after that check passes. A release
/// that is not newer than the running version is never offered (no downgrades).
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

    /// Where an interactive check was started from — controls which surface
    /// shows the outcome (menu -> main-window alerts; Settings has its own
    /// inline status line).
    enum CheckOrigin { case menu, settings }

    @Published var phase: Phase = .idle
    @Published var availableRelease: GitHubRelease?
    @Published var showUpdatePrompt = false
    @Published var menuInitiatedCheck = false

    private var updateTask: Task<Void, Never>?

    static let repo = "keitheobrien/movie_tagger"
    static let teamID = "9R236BB67S"
    private static let lastCheckKey = "last_update_check"
    static let autoCheckKey = "auto_update_check"
    private static let checkInterval: TimeInterval = 20 * 60 * 60   // ~daily

    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// True while an update is being downloaded or installed.
    var isBusy: Bool {
        if case .downloading = phase { return true }
        return phase == .installing
    }

    // MARK: Checking

    /// Launch-time check: silent unless a newer release is found.
    func checkAutomatically() async {
        guard UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil
                || UserDefaults.standard.bool(forKey: Self.autoCheckKey) else {
            log.notice("auto-check disabled by preference")
            return
        }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        #if DEBUG
        let forced = Self.debugFlag("MOVIETAGGER_FORCE_UPDATE")   // also skips the throttle
        #else
        let forced = false
        #endif
        guard forced || Date().timeIntervalSince(last) > Self.checkInterval else {
            log.notice("auto-check skipped: last check \(last) is within the interval")
            return
        }

        menuInitiatedCheck = false
        do {
            if let release = try await fetchNewerRelease() {
                availableRelease = release
                showUpdatePrompt = true
                #if DEBUG
                // End-to-end test hook: accept the update without a click.
                if Self.debugFlag("MOVIETAGGER_AUTO_ACCEPT_UPDATE", oneShot: true) {
                    log.notice("DEBUG auto-accept hook: starting update")
                    performUpdate(release)
                }
                #endif
            } else {
                log.notice("auto-check: up to date (\(self.currentVersionString))")
            }
        } catch {
            // Silent for the user on the automatic path — but not for the log.
            log.error("auto-check failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// Test hooks read the environment or, since `open` can't pass env vars,
    /// a matching UserDefaults key (`defaults write com.movietagger.app <flag> -bool YES`).
    /// `oneShot` clears the defaults key on read, so a forgotten flag can't keep
    /// replacing Debug builds on every launch.
    private static func debugFlag(_ name: String, oneShot: Bool = false) -> Bool {
        if ProcessInfo.processInfo.environment[name] == "1" { return true }
        guard UserDefaults.standard.bool(forKey: name) else { return false }
        if oneShot { UserDefaults.standard.removeObject(forKey: name) }
        return true
    }
    #endif

    /// User-initiated check: everything is surfaced.
    func checkInteractively(origin: CheckOrigin = .settings) async {
        guard phase != .checking, !isBusy else { return }
        menuInitiatedCheck = origin == .menu
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
    /// running version. In DEBUG builds, MOVIETAGGER_FORCE_UPDATE=1 skips the
    /// version gate (never the signature gate) so the full flow can be tested
    /// against the current release.
    private func fetchNewerRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed("release feed returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        // Stamp only after a successful check, so a launch-time network
        // failure doesn't suppress retries for the next ~20 hours.
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        #if DEBUG
        let force = Self.debugFlag("MOVIETAGGER_FORCE_UPDATE")
        #else
        let force = false
        #endif
        log.notice("latest release \(release.tagName), running \(self.currentVersionString)\(force ? " (forced)" : "")")
        guard let remote = AppVersion(release.tagName),
              let current = AppVersion(currentVersionString) else { return force ? release : nil }
        return (remote > current || force) ? release : nil
    }

    // MARK: Update flow (download -> verify -> install -> relaunch)

    /// Installed by the app: true while the app must not be replaced and quit
    /// (a metadata write into the user's file is in flight).
    var installGate: () -> Bool = { false }

    func performUpdate(_ release: GitHubRelease) {
        guard updateTask == nil else { return }
        guard !installGate() else {
            phase = .failed("Finish the current metadata write before updating.")
            return
        }
        updateTask = Task {
            await runUpdate(release)
            updateTask = nil
        }
    }

    /// Cancels a download in progress. Installation is the point of no return.
    func cancelUpdate() {
        updateTask?.cancel()
    }

    private func runUpdate(_ release: GitHubRelease) async {
        let pid = ProcessInfo.processInfo.processIdentifier
        let tmp = FileManager.default.temporaryDirectory
        let zipURL = tmp.appendingPathComponent("MovieTagger-update-\(pid).zip")
        let extractDir = tmp.appendingPathComponent("MovieTagger-update-extract-\(pid)")

        func cleanupTemp() {
            try? FileManager.default.removeItem(at: zipURL)
            try? FileManager.default.removeItem(at: extractDir)
        }

        do {
            guard let asset = release.appAsset else { throw UpdateError.noAsset }

            log.notice("update \(release.tagName): downloading \(asset.name)")
            phase = .downloading(0)
            try await Self.download(asset, to: zipURL) { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(progress)
                }
            }

            log.notice("download complete; extracting and verifying signature")
            phase = .installing
            let newApp = try await Task.detached(priority: .userInitiated) {
                let app = try Self.extractApp(from: zipURL, into: extractDir)
                try Self.verifyCodeSignature(at: app, teamID: Self.teamID)
                Self.removeQuarantine(at: app)   // only after verification
                return app
            }.value

            log.notice("signature verified; installing")
            let (installedURL, backup) = try Self.install(newApp: newApp)
            cleanupTemp()   // before relaunch — terminate may not return
            log.notice("installed at \(installedURL.path); relaunching")
            relaunch(at: installedURL, removingBackup: backup)
        } catch is CancellationError {
            log.notice("update cancelled")
            cleanupTemp()
            phase = .idle
        } catch let error as URLError where error.code == .cancelled {
            log.notice("update cancelled")
            cleanupTemp()
            phase = .idle
        } catch {
            log.error("update failed: \(error.localizedDescription)")
            cleanupTemp()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Chunked download off the main actor; progress lands back on it via the
    /// callback. Cooperatively cancellable.
    private nonisolated static func download(
        _ asset: GitHubRelease.Asset,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: asset.browserDownloadUrl), url.scheme == "https" else {
            throw UpdateError.downloadFailed("invalid asset URL")
        }

        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let expected = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : asset.size
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var received = 0
        var buffer = Data(capacity: 256 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                received += buffer.count
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    progress(min(1, Double(received) / Double(expected)))
                }
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1)
    }

    private nonisolated static func extractApp(from zipURL: URL, into dir: URL) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.extractionFailed("ditto exited with status \(ditto.terminationStatus)")
        }

        // Must be a real directory bundle — not a symlink pointing elsewhere.
        let app = dir.appendingPathComponent("MovieTagger.app")
        let values = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else {
            throw UpdateError.extractionFailed("archive did not contain a valid MovieTagger.app bundle")
        }
        return app
    }

    /// Hard gate: the bundle must be validly signed by THIS team. A tampered,
    /// re-signed, or unsigned download is rejected and deleted.
    private nonisolated static func verifyCodeSignature(at appURL: URL, teamID: String) throws {
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
    private nonisolated static func install(newApp: URL) throws -> (installed: URL, backup: URL) {
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
        // The backup IS the running process's bundle — it must stay on disk
        // until this process has exited (the relaunch helper removes it).
        return (currentURL, backup)
    }

    private func relaunch(at appURL: URL, removingBackup backup: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for THIS process to fully exit (no fixed-sleep race), launch the
        // new copy, and only then remove the old bundle we're still running
        // from. "$0"/"$1" keep the paths out of shell interpretation.
        // `open -n` forces a fresh instance even if LaunchServices still lists
        // the dead pid for a moment (plain `open` would just "activate" it and
        // nothing would relaunch); one retry covers that window. $1 is the
        // whole staging directory the backup lives in — ours alone.
        sh.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; "
                + "/usr/bin/open -n \"$0\" || { /bin/sleep 1; /usr/bin/open -n \"$0\"; }; "
                + "/bin/rm -rf \"$1\"",
            appURL.path,
            backup.deletingLastPathComponent().path,
        ]
        do {
            try sh.run()
        } catch {
            // Don't quit into nothing: the new version is installed at the
            // original path, the user just has to reopen it.
            log.error("could not start relaunch helper: \(error.localizedDescription)")
            phase = .failed("The update was installed, but MovieTagger couldn\u{2019}t relaunch itself. Quit and reopen it to finish.")
            return
        }

        // NSApp.terminate(nil) is silently refused while a sheet is presented
        // (reproduced: it returns and the app keeps running), so dismiss the
        // update sheet first and terminate once that has committed. If AppKit
        // still declines, exit outright — the install is complete and the
        // helper above relaunches the new version the moment we're gone.
        showUpdatePrompt = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            log.notice("terminating for relaunch")
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                log.error("NSApp.terminate was refused; exiting directly")
                exit(0)
            }
        }
    }
}
