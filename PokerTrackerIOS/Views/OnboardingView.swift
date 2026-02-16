//
//  OnboardingView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)
            Text("Poker Tracker")
                .font(.title)
                .fontWeight(.bold)
            Text("Log sessions, track your bankroll, and view stats.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                isComplete = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.accent)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
