//
//  SettingsStore.swift
//  PokerTrackerIOS
//
//  Persists app settings
//

import Foundation
import SwiftUI

class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }
    
    private static let settingsKey = "poker_settings"
    private static let settingsUpdatedAtKey = "poker_settings_updated_at"
    private static let cloudSettingsKey = "icloud_poker_settings"
    private static let cloudSettingsUpdatedAtKey = "icloud_poker_settings_updated_at"
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var isApplyingCloudSync = false
    private var cloudSyncUpdatedAt: TimeInterval?
    
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }

        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromCloudIfNewer()
        }
        DispatchQueue.main.async { [weak self] in
            self?.cloudStore.synchronize()
            self?.syncFromCloudIfNewer()
        }
    }

    deinit {
        if let observer = cloudObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    var currentBankroll: Double {
        settings.startingBankroll
    }
    
    private func save() {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        let updatedAt = cloudSyncUpdatedAt ?? Date().timeIntervalSince1970

        UserDefaults.standard.set(encoded, forKey: Self.settingsKey)
        UserDefaults.standard.set(updatedAt, forKey: Self.settingsUpdatedAtKey)

        guard !isApplyingCloudSync else { return }
        cloudStore.set(encoded, forKey: Self.cloudSettingsKey)
        cloudStore.set(updatedAt, forKey: Self.cloudSettingsUpdatedAtKey)
        cloudStore.synchronize()
    }

    private func syncFromCloudIfNewer() {
        let cloudUpdatedAt = cloudStore.double(forKey: Self.cloudSettingsUpdatedAtKey)
        let localUpdatedAt = UserDefaults.standard.double(forKey: Self.settingsUpdatedAtKey)
        guard cloudUpdatedAt > localUpdatedAt else { return }
        guard let cloudData = cloudStore.data(forKey: Self.cloudSettingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: cloudData) else { return }

        isApplyingCloudSync = true
        cloudSyncUpdatedAt = cloudUpdatedAt
        settings = decoded
        cloudSyncUpdatedAt = nil
        isApplyingCloudSync = false
    }
}
