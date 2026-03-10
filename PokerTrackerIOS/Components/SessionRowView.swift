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
    private var resultColor: Color { session.isWin ? winColor : lossColor }
    
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
        HStack(spacing: 12) {
            if settingsStore.settings.showSessionNumbers {
                Text("#\(displayNumber ?? 0)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [resultColor, resultColor.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(amountText)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(resultColor)

                    Spacer(minLength: 8)

                    Text(session.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    Text(gameInfoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let hours = session.hoursPlayed, hours > 0 {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("\(String(format: "%.1f", hours))h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let venue = session.venue, !venue.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 9))
                        Text(venue)
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }

                if !session.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(session.tags.prefix(3), id: \.self) { tag in
                            if let t = SessionTag(rawValue: tag) {
                                HStack(spacing: 2) {
                                    Image(systemName: t.icon)
                                    Text(t.rawValue)
                                }
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(t.color.opacity(0.12))
                                .foregroundStyle(t.color)
                                .clipShape(Capsule())
                            }
                        }
                        if session.tags.count > 3 {
                            Text("+\(session.tags.count - 3)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardStyle()
    }
}
