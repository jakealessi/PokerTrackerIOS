//
//  PokerTrackerIOSApp.swift
//  PokerTrackerIOS
//

import LocalAuthentication
import SwiftUI

@main
struct PokerTrackerIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var routeController = AppRouteController()
    @StateObject private var appLock = AppLockController()
    
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
                            .environmentObject(routeController)
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

                if appLock.isLocked {
                    AppLockView(
                        isAuthenticating: appLock.isAuthenticating,
                        message: appLock.message,
                        unlockAction: {
                            appLock.authenticateIfNeeded(isEnabled: shouldUsePrivacyLock)
                        }
                    )
                }
            }
            .onAppear {
                appLock.configure(isEnabled: shouldUsePrivacyLock)
                refreshWidgets()
                consumeWidgetRoute()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshReminder() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    appLock.authenticateIfNeeded(isEnabled: shouldUsePrivacyLock)
                    consumeWidgetRoute()
                case .background:
                    appLock.lockIfNeeded(isEnabled: shouldUsePrivacyLock)
                case .inactive:
                    if !appLock.isAuthenticating {
                        appLock.lockIfNeeded(isEnabled: shouldUsePrivacyLock)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: settingsStore.settings.privacyModeEnabled) { _, _ in
                appLock.configure(isEnabled: shouldUsePrivacyLock)
            }
            .onChange(of: settingsStore.settings.hasSeenOnboarding) { _, _ in
                appLock.configure(isEnabled: shouldUsePrivacyLock)
                refreshWidgets()
            }
            .onChange(of: settingsStore.settings.currency) { _, _ in refreshWidgets() }
            .onChange(of: settingsStore.settings.startingBankroll) { _, _ in refreshWidgets() }
            .onChange(of: settingsStore.settings.deductExpensesFromProfit) { _, _ in refreshWidgets() }
            .onChange(of: settingsStore.settings.showHourlyRate) { _, _ in refreshWidgets() }
            .onChange(of: settingsStore.settings.useCompactCurrency) { _, _ in refreshWidgets() }
            .onChange(of: settingsStore.settings.reminderEnabled) { _, _ in refreshReminder() }
            .onChange(of: sessionStore.dataVersion) { _, _ in
                refreshReminder()
                refreshWidgets()
            }
        }
    }

    private var shouldUsePrivacyLock: Bool {
        settingsStore.settings.privacyModeEnabled && settingsStore.settings.hasSeenOnboarding
    }

    private func refreshReminder() {
        let lastDate = sessionStore.sessions.map(\.date).max()
        ReminderManager.scheduleIfNeeded(
            enabled: settingsStore.settings.reminderEnabled,
            lastSessionDate: lastDate
        )
    }

    private func refreshWidgets() {
        PokerWidgetSnapshotStore.refresh(
            sessions: sessionStore.sessions,
            settings: settingsStore.settings
        )
    }

    private func consumeWidgetRoute() {
        guard settingsStore.settings.hasSeenOnboarding,
              let route = PokerWidgetRouteStore.consumePendingRoute() else { return }
        routeController.pendingRoute = route
    }
}

@MainActor
private final class AppLockController: ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var message: String?

    func configure(isEnabled: Bool) {
        if isEnabled {
            lockIfNeeded(isEnabled: true)
            authenticateIfNeeded(isEnabled: true)
        } else {
            isLocked = false
            isAuthenticating = false
            message = nil
        }
    }

    func lockIfNeeded(isEnabled: Bool) {
        guard isEnabled else {
            isLocked = false
            isAuthenticating = false
            message = nil
            return
        }
        isLocked = true
    }

    func authenticateIfNeeded(isEnabled: Bool) {
        guard isEnabled else {
            isLocked = false
            isAuthenticating = false
            message = nil
            return
        }
        guard isLocked, !isAuthenticating else { return }

        isAuthenticating = true
        message = nil

        Task {
            let context = LAContext()
            context.localizedCancelTitle = "Cancel"

            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                await MainActor.run {
                    self.isLocked = false
                    self.isAuthenticating = false
                    self.message = authError?.localizedDescription ?? "Face ID or device passcode is unavailable."
                }
                return
            }

            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock Poker Bankroll AI."
                )
                await MainActor.run {
                    self.isAuthenticating = false
                    if success {
                        self.isLocked = false
                        self.message = nil
                    } else {
                        self.message = "Authentication failed."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.message = error.localizedDescription
                }
            }
        }
    }
}

private struct AppLockView: View {
    let isAuthenticating: Bool
    let message: String?
    let unlockAction: () -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(AppTheme.accent)

                VStack(spacing: 6) {
                    Text("Privacy Mode")
                        .font(.title2.weight(.semibold))
                    Text("Unlock with Face ID or your device passcode.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isAuthenticating {
                    ProgressView()
                        .tint(AppTheme.accent)
                } else {
                    Button {
                        unlockAction()
                    } label: {
                        Label("Unlock", systemImage: "faceid")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.large)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
    }
}
