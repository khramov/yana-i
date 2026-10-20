import Foundation
import Testing

struct EntitlementsTests {
    private let entitlements: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/YanaMac.entitlements")
        let data = try! Data(contentsOf: url)
        return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }()

    @Test func listsExactlyTheDesignedCapabilities() {
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.network.client",
            "com.apple.security.files.user-selected.read-only",
            "com.apple.developer.icloud-services",
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.aps-environment",
        ])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool == true)
        #expect(entitlements["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"])
        #expect(entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] == ["$(YANA_CLOUDKIT_CONTAINER)"])
    }
}
