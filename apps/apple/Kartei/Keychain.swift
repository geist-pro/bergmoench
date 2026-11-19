// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Security

/// Small wrapper over generic-password Keychain items. Holds the sync host key, never a password.
struct Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    let service: String
    #if DEBUG
    /// Scripted test runs (KARTEI_DATA_DIR) keep the key in a file in their scratch folder: an ad-hoc build gets a
    /// new code signature on every rebuild, and the login keychain would then ask the person to allow access.
    var debugFolder: URL? = nil

    private func debugFile(_ account: String) -> URL? {
        debugFolder?.appendingPathComponent("keychain-\(service)-\(account.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")).json")
    }
    #endif

    #if os(macOS)
    /// The data-protection keychain needs a signed team identity (an application identifier); ad-hoc local builds
    /// use the login keychain instead.
    static let dataProtection: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) != nil
            || SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) != nil
    }()
    #endif

    private func base(_ account: String) -> [CFString: Any] {
        var q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        #if os(macOS)
        if Self.dataProtection { q[kSecUseDataProtectionKeychain] = true }
        #endif
        return q
    }

    func set(_ data: Data, for account: String) throws {
        #if DEBUG
        if let f = debugFile(account) { try data.write(to: f, options: .atomic); return }
        #endif
        let q = base(account)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func data(for account: String) throws -> Data? {
        #if DEBUG
        if let f = debugFile(account) { return try? Data(contentsOf: f) }
        #endif
        var q = base(account)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        // Never block on an access prompt (e.g. the app's signature changed): fail, and the app asks to log in again.
        q[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        let out = result as? Data
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return out
    }

    func remove(_ account: String) throws {
        #if DEBUG
        if let f = debugFile(account) { try? FileManager.default.removeItem(at: f); return }
        #endif
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    func set<T: Encodable>(_ value: T, for account: String) throws { try set(JSONEncoder().encode(value), for: account) }

    func value<T: Decodable>(_ type: T.Type, for account: String) throws -> T? {
        guard let data = try data(for: account) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
