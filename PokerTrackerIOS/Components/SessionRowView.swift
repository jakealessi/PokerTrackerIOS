//
//  SessionRowView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct SessionRowView: View {
    let session: PokerSession
    var currency: String = "USD"
    
    var body: some View {
        HStack {
            Image(systemName: session.isWin ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(session.isWin ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(PokerSession.formatCurrency(session.amount, currency: currency))
                    .font(.headline)
                    .foregroundStyle(session.isWin ? .green : .red)
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
