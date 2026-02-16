//
//  PokerTrackerIOSApp.swift
//  PokerTrackerIOS
//

import SwiftUI

@main
struct PokerTrackerIOSApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var settingsStore = SettingsStore()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if settingsStore.settings.hasSeenOnboarding {
                    MainTabView()
                        .environmentObject(sessionStore)
                        .environmentObject(settingsStore)
                } else {
                    OnboardingView(isComplete: Binding(
                        get: { settingsStore.settings.hasSeenOnboarding },
                        set: { val in
                            var s = settingsStore.settings
                            s.hasSeenOnboarding = val
                            settingsStore.settings = s
                        }
                    ))
                    .environmentObject(settingsStore)
                }
            }
        }
    }
}
