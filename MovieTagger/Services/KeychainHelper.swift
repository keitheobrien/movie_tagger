import Foundation
import CryptoKit
import IOKit

/// Stores the API key in an encrypted file in Application Support.
/// No Keychain = no system password prompts.
enum KeychainHelper {

    private static let fileName = ".tmdb_credentials"

    // MARK: - Public API (same interface as before)

    static func save(apiKey: String) throws {
        let dir = try storageDirectory()
        let fileURL = dir.appendingPathComponent(fileName)
        guard let plaintext = apiKey.data(using: .utf8) else { return }

        let key = deriveKey()
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        try sealed.combined.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])

        // Restrict file permissions to owner only (0600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    static func load() -> String? {
        let dir = (try? storageDirectory()) ?? FileManager.default.temporaryDirectory
        let fileURL = dir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let combined = try? Data(contentsOf: fileURL) else { return nil }

        let key = deriveKey()
        guard let sealedBox = try? ChaChaPoly.SealedBox(combined: combined),
              let plaintext = try? ChaChaPoly.open(sealedBox, using: key) else { return nil }

        return String(data: plaintext, encoding: .utf8)
    }

    static func delete() {
        let dir = (try? storageDirectory()) ?? FileManager.default.temporaryDirectory
        let fileURL = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    /// ~/Library/Application Support/MovieTagger/
    private static func storageDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("MovieTagger")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Derive a stable 256-bit encryption key from the hardware UUID.
    /// This ties the encrypted file to this specific Mac — it can't be
    /// decrypted if the file is copied to another machine.
    private static func deriveKey() -> SymmetricKey {
        let uuid = hardwareUUID() ?? "com.movietagger.fallback-key"
        let salt = "com.movietagger.credential.salt"
        let material = "\(uuid).\(salt)"
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    /// Read the hardware UUID via IOKit (stable per-machine identifier).
    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let cfUUID = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )
        return cfUUID?.takeRetainedValue() as? String
    }
}
