//
//  DashboardView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingAddSession = false
    @State private var aiPrompt = ""
    @State private var isAILoading = false
    @State private var aiError: String?
    @State private var aiWarning: String?
    
    private var bankroll: Double {
        settingsStore.settings.startingBankroll + sessionStore.totalProfit
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top info
                VStack(spacing: 16) {
                    // Bankroll
                    VStack(spacing: 2) {
                        Text("Bankroll")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(PokerSession.formatCurrency(bankroll, currency: settingsStore.settings.currency))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(bankroll >= 0 ? .green : .red)
                        Text("P/L: \(PokerSession.formatCurrency(sessionStore.totalProfit, currency: settingsStore.settings.currency))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.top, 8)
                    
                    // Quick stats row
                    HStack(spacing: 0) {
                        statItem("\(sessionStore.totalSessions)", "Sessions")
                        Divider().frame(height: 30)
                        statItem(String(format: "%.0f%%", sessionStore.winRate), "Win Rate")
                        Divider().frame(height: 30)
                        statItem("\(sessionStore.winCount)/\(sessionStore.lossCount)", "W/L")
                        if sessionStore.totalHoursPlayed > 0, let rate = sessionStore.hourlyRate {
                            Divider().frame(height: 30)
                            statItem(PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency), "$/hr")
                        }
                    }
                    .padding(.vertical, 10)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // AI session logger at bottom
                VStack(spacing: 10) {
                    if let warning = aiWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    if let error = aiError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Log a session...", text: $aiPrompt, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(10)
                        
                        Button {
                            Task { await logWithAI() }
                        } label: {
                            Group {
                                if isAILoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .background(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAILoading ? Color.gray : AppTheme.accent)
                            .foregroundStyle(.white)
                            .cornerRadius(22)
                        }
                        .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAILoading)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Poker Tracker")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSession = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) { AddSessionView() }
        }
    }
    
    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func logWithAI() async {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        aiError = nil
        aiWarning = nil
        isAILoading = true
        
        do {
            let result = try await AISessionService.shared.parseSession(
                from: prompt,
                geminiKey: settingsStore.settings.geminiAPIKey ?? APIKeysLoader.geminiKey,
                openAIKey: settingsStore.settings.openAIAPIKey ?? APIKeysLoader.openAIKey
            )
            let session = PokerSession(
                amount: result.session.amount,
                date: Date(),
                notes: result.session.notes ?? "",
                gameType: result.session.gameType,
                variant: result.session.variant,
                hoursPlayed: result.session.hoursPlayed,
                stakes: result.session.stakes,
                venue: result.session.venue
            )
            sessionStore.addSession(session)
            if result.usedFallback {
                aiWarning = result.fallbackReason
            }
            if settingsStore.settings.hapticFeedback { HapticManager.success() }
            aiPrompt = ""
        } catch {
            aiError = error.localizedDescription
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        }
        
        isAILoading = false
    }
}

#Preview {
    DashboardView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
