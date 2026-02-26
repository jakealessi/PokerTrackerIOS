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
    
    private var gameInfoText: String {
        var parts: [String] = [session.displayVariantAbbreviation, session.gameType.abbreviation]
        if let stakes = session.stakes, !stakes.isEmpty {
            parts.append(stakes)
        }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        if settingsStore.settings.useCompactCurrency {
            let prefix = session.amount > 0 ? "+" : (session.amount < 0 ? "-" : "")
            return prefix + PokerSession.formatCompactCurrency(abs(session.amount), currency: currency)
        }
        return PokerSession.formatCurrency(session.amount, currency: currency)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if settingsStore.settings.showSessionNumbers {
                // Session number badge (dynamic: earliest = #1)
                Text("#\(displayNumber ?? 0)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(session.isWin ? winColor : lossColor)
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(amountText)
                    .font(.headline)
                    .foregroundStyle(session.isWin ? winColor : lossColor)
                
                Text(gameInfoText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                
                if let venue = session.venue, !venue.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle")
                            .font(.caption2)
                        Text(venue)
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
                }
            }
            
            Spacer(minLength: 8)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                if let hours = session.hoursPlayed, hours > 0 {
                    Text("\(String(format: "%.1f", hours)) hrs")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(6)
    }
}
