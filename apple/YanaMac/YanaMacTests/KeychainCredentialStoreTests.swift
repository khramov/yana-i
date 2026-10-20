import Foundation
import Security
import Testing
@testable import YanaMac

/// The data-protection Keychain needs a host app signed with a development team; unsigned builds
/// (`CODE_SIGNING_ALLOWED=NO`) get `errSecMissingEntitlement`.
private let keychainAvailable: Bool = {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "yana.tests.probe",
                                kSecAttrAccount as String: UUID().uuidString, kSecUseDataProtectionKeychain as String: true]
    var item = query
    item[kSecValueData as String] = Data("probe".utf8)
    let status = SecItemAdd(item as CFDictionary, nil)
    SecItemDelete(query as CFDictionary)
    return status != errSecMissingEntitlement
}()

@Suite(.serialized, .enabled(if: keychainAvailable, "Requires a test host signed with a development team (see apple/README.md)"))
struct KeychainCredentialStoreTests {
    private let store = KeychainCredentialStore(service: "yana.tests.\(UUID().uuidString)")

    @Test func saveReplaceRemove() throws {
        defer { try? store.remove(for: "keyed") }
        #expect(try store.credential(for: "keyed") == nil)
        try store.save("first-secret", for: "keyed")
        #expect(try store.credential(for: "keyed") == "first-secret")
        try store.save("second-secret", for: "keyed")
        #expect(try store.credential(for: "keyed") == "second-secret")
        try store.remove(for: "keyed")
        #expect(try store.credential(for: "keyed") == nil)
        try store.remove(for: "keyed")
    }

    @Test func itemIsNotSynchronizableAndThisDeviceOnly() throws {
        defer { try? store.remove(for: "keyed") }
        try store.save("secret", for: "keyed")
        let attributes = try #require(try store.attributes(for: "keyed"))
        let synchronizable = attributes[kSecAttrSynchronizable as String]
        #expect((synchronizable as? Bool ?? (synchronizable as? NSNumber)?.boolValue) == false)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecValueData as String] == nil)
    }

    @Test func providersAreIsolated() throws {
        defer { try? store.remove(for: "a"); try? store.remove(for: "b") }
        try store.save("one", for: "a")
        try store.save("two", for: "b")
        try store.remove(for: "a")
        #expect(try store.credential(for: "a") == nil)
        #expect(try store.credential(for: "b") == "two")
    }
}
