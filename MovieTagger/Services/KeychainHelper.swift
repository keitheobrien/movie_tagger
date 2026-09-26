import Foundation
import Security
import CryptoKit
import IOKit

protocol CredentialStorage {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

/// Migration never deletes the legacy credential until Keychain accepted it.
struct MigratingCredentialStore {
    let primary: any CredentialStorage
    let legacy: any CredentialStorage

    func load() throws -> String? {
        if let value = try primary.load() {
            try legacy.delete()
            return value
        }
        guard let value = try legacy.load() else { return nil }
        try save(value)
        return value
    }

    func save(_ value: String) throws {
        try primary.save(value)
        try legacy.delete()
    }

    func delete() throws {
        // Delete the migration source first so a partial failure can't resurrect it.
        try legacy.delete()
        try primary.delete()
    }
}

enum KeychainHelper {
    private static var store: MigratingCredentialStore {
        MigratingCredentialStore(primary: SystemKeychain(), legacy: LegacyCredentialFile())
    }
    static func load() throws -> String? { try store.load() }
    static func save(apiKey: String) throws { try store.save(apiKey) }
    static func delete() throws { try store.delete() }
}

private struct SystemKeychain: CredentialStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.movietagger.app",
         kSecAttrAccount as String: "tmdb-api-key"]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    func save(_ value: String) throws {
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "Error \(status)")
            ])
        }
    }
}

private struct LegacyCredentialFile: CredentialStorage {
    private static let fileName = ".tmdb_credentials"

    func load() throws -> String? {
        let url = try Self.storageDirectory().appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let combined = try Data(contentsOf: url)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(sealedBox, using: Self.deriveKey())
        return String(data: plaintext, encoding: .utf8)
    }

    func save(_ value: String) throws {
        // The legacy store is read-only; new credentials only go into Keychain.
        throw CocoaError(.fileWriteNoPermission)
    }

    func delete() throws {
        let url = try Self.storageDirectory().appendingPathComponent(Self.fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

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

    /// Reproduce the old derivation only to migrate existing credential files.
    /// A hardware identifier is not a secret; never use this for new storage.
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
