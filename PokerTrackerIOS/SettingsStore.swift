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
    
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }
    
    var currentBankroll: Double {
        settings.startingBankroll
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: Self.settingsKey)
        }
    }
}
