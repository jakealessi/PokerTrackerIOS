//
//  AnonymousUserID.swift
//  PokerTrackerIOS
//
//  Stable anonymous user identity persisted in Keychain (UserDefaults fallback).
//

import Foundation
import Security

enum AnonymousUserID {
    private static let service = "com.pokertracker.anonymous-user-id"
    private static let account = "userId"
    private static let udKey = "anonymous_user_id"

    static func getOrCreate() -> String {
        if let id = loadFromKeychain() { return id }
        if let id = UserDefaults.standard.string(forKey: udKey), !id.isEmpty {
            saveToKeychain(id)
            return id
        }
        let id = UUID().uuidString
        saveToKeychain(id)
        UserDefaults.standard.set(id, forKey: udKey)
        return id
    }

    // MARK: - Keychain

    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete any existing item, then add
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
