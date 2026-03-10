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
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea(.all)
                Group {
                    if settingsStore.settings.hasSeenOnboarding {
                        MainTabView()
                            .environmentObject(sessionStore)
                            .environmentObject(settingsStore)
                            .environmentObject(SubscriptionStore.shared)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshReminder() }
            }
            .onChange(of: settingsStore.settings.reminderEnabled) { _, _ in refreshReminder() }
            .onChange(of: sessionStore.dataVersion) { _, _ in refreshReminder() }
        }
    }

    private func refreshReminder() {
        let lastDate = sessionStore.sessions.map(\.date).max()
        ReminderManager.scheduleIfNeeded(
            enabled: settingsStore.settings.reminderEnabled,
            lastSessionDate: lastDate
        )
    }
}
