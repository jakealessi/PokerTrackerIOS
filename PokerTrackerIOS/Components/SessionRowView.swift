//
//  SessionRowView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct SessionRowView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let session: PokerSession
    var displayNumber: Int?
    var currency: String = "USD"
    
    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }
    
    var body: some View {
        HStack {
            // Session number badge (dynamic: earliest = #1)
            Text("#\(displayNumber ?? 0)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(session.isWin ? winColor : lossColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(PokerSession.formatCurrency(session.amount, currency: currency))
                    .font(.headline)
                    .foregroundStyle(session.isWin ? winColor : lossColor)
                HStack(spacing: 4) {
                    Text(session.displayVariant)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(session.gameType.rawValue)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let stakes = session.stakes, !stakes.isEmpty {
                        Text("• \(stakes)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            
            Spacer()
            
            Text(session.date, style: .date)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(6)
    }
}
