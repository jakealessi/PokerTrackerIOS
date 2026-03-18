//
//  OnboardingView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @EnvironmentObject var settingsStore: SettingsStore
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                }

                Text("Poker Bankroll AI")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Track sessions, analyze stats, and improve your game.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                featureRow(icon: "bubble.left.and.bubble.right.fill", title: "AI Session Logging", subtitle: "Describe your session — AI does the rest")
                featureRow(icon: "chart.bar.fill", title: "Stats & Charts", subtitle: "Profit curves, win rates, and streaks")
                featureRow(icon: "percent", title: "Odds Calculator", subtitle: "NLH, PLO, and 5-Card PLO equity")
                featureRow(icon: "calendar", title: "Calendar View", subtitle: "See your sessions day by day")
            }
            .padding(.horizontal, 28)

            Spacer()

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                isComplete = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
