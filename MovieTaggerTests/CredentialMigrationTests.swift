import XCTest
@testable import MovieTagger

private final class MemoryCredentials: CredentialStorage {
    var value: String?
    var failSave = false
    var failDelete = false
    init(_ value: String? = nil) { self.value = value }
    func load() throws -> String? { value }
    func save(_ value: String) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        self.value = value
    }
    func delete() throws {
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        value = nil
    }
}

final class CredentialMigrationTests: XCTestCase {
    func testMigratesLegacyKeyOnlyAfterSuccessfulKeychainSave() throws {
        let primary = MemoryCredentials()
        let legacy = MemoryCredentials("test-key")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        primary.failSave = true
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(legacy.value, "test-key")
        primary.failSave = false
        XCTAssertEqual(try store.load(), "test-key")
        XCTAssertEqual(primary.value, "test-key")
        XCTAssertNil(legacy.value)
    }

    func testExistingKeychainEntryTakesPrecedence() throws {
        let primary = MemoryCredentials("new-key")
        let legacy = MemoryCredentials("old-key")
        XCTAssertEqual(try MigratingCredentialStore(primary: primary, legacy: legacy).load(), "new-key")
        XCTAssertNil(legacy.value)
    }

    func testRemovalCannotResurrectLegacyKey() throws {
        let primary = MemoryCredentials("key")
        let legacy = MemoryCredentials("key")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        legacy.failDelete = true
        XCTAssertThrowsError(try store.delete())
        XCTAssertEqual(primary.value, "key")
        legacy.failDelete = false
        try store.delete()
        XCTAssertNil(try store.load())
    }
}
