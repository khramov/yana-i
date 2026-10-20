import CryptoKit
import Foundation

extension UUID {
    /// Name-based UUID version 5 (SHA-1), per RFC 4122 §4.3.
    public static func v5(namespace: UUID, name: String) -> UUID {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Derived identities, so two devices creating the same holding or goal offline produce the same record ID.
public enum RecordIdentity {
    /// Fixed namespace for Yana's derived IDs. Never change it: every stored ID depends on it.
    public static let namespace = UUID(uuidString: "6B1E3C0A-5F2D-4C8E-9A7B-3D4F5E6A7B8C")!

    /// Trimmed and upper-cased ticker.
    public static func normalizeTicker(_ ticker: String) -> String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func holdingID(portfolioID: UUID, ticker: String) -> UUID {
        UUID.v5(namespace: namespace, name: "holding|\(portfolioID.uuidString.lowercased())|\(normalizeTicker(ticker))")
    }

    /// Goal key as stored: the normalized ticker for holding goals, the asset-class raw value otherwise.
    public static func normalizeGoalKey(_ key: String, scope: GoalScope) -> String {
        switch scope {
        case .holding: return normalizeTicker(key)
        case .assetClass: return key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    public static func goalID(portfolioID: UUID, scope: GoalScope, key: String) -> UUID {
        let normalized = normalizeGoalKey(key, scope: scope)
        return UUID.v5(namespace: namespace, name: "goal|\(portfolioID.uuidString.lowercased())|\(scope.rawValue)|\(normalized)")
    }
}
