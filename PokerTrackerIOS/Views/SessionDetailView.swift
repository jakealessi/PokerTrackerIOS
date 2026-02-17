//
//  SessionDetailView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    let session: PokerSession
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                amountCard
                detailsSection
                if !session.notes.isEmpty { notesSection(session.notes) }
                if let handNotes = session.handNotes, !handNotes.isEmpty { handNotesSection(handNotes) }
            }
            .padding()
        }
        .navigationTitle(session.displayVariant)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.displayVariant)
                    .font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    ShareLink(item: sessionShareText, subject: Text("Poker Session"), message: Text(sessionShareText)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditSessionView(session: session)
        }
        .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                sessionStore.deleteSession(session)
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
    
    private var amountCard: some View {
        VStack(spacing: 8) {
            Text("Session #\(sessionStore.displayNumber(for: session) ?? 0)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(PokerSession.formatCurrency(session.amount, currency: settingsStore.settings.currency))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(session.isWin ? settingsStore.settings.profitLossColorScheme.winColor : settingsStore.settings.profitLossColorScheme.lossColor)
            Text(session.date, style: .date)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.cardBackground)
        )
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 8) {
                detailRow("Format", session.gameType.rawValue)
                detailRow("Variant", session.displayVariant)
                if let hours = session.hoursPlayed {
                    detailRow("Hours Played", "\(String(format: "%.1f", hours))")
                    if let rate = session.hourlyRate {
                        detailRow("Hourly Rate", PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency) + "/hr")
                    }
                }
                if let stakes = session.stakes, !stakes.isEmpty {
                    detailRow("Stakes", stakes)
                }
                if let venue = session.venue, !venue.isEmpty {
                    detailRow("Venue", venue)
                }
                if let buyIn = session.buyIn {
                    detailRow("Buy-in", PokerSession.formatCurrency(buyIn, currency: settingsStore.settings.currency))
                }
                if let cashOut = session.cashOut {
                    detailRow("Cash Out", PokerSession.formatCurrency(cashOut, currency: settingsStore.settings.currency))
                }
                if let pos = session.tournamentPosition {
                    detailRow("Position", "\(pos)")
                }
                if let rebuys = session.rebuys, rebuys > 0 {
                    detailRow("Rebuys", "\(rebuys)")
                }
                if let roi = session.tournamentROI {
                    detailRow("ROI", String(format: "%.0f%%", roi))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            )
        }
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
        }
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            Text(notes)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        )
    }
    
    private func handNotesSection(_ handNotes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hand Notes")
                .font(.headline)
            Text(handNotes)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        )
    }
    
    private var sessionShareText: String {
        var lines = [
            "\(session.displayVariant) \(session.gameType.rawValue) • \(PokerSession.formatCurrency(session.amount, currency: settingsStore.settings.currency))",
            session.date.formatted(date: .long, time: .omitted)
        ]
        if let stakes = session.stakes, !stakes.isEmpty { lines.append("Stakes: \(stakes)") }
        if let venue = session.venue, !venue.isEmpty { lines.append("Venue: \(venue)") }
        if let hours = session.hoursPlayed { lines.append("Hours: \(String(format: "%.1f", hours))") }
        if let roi = session.tournamentROI { lines.append("ROI: \(String(format: "%.0f%%", roi))") }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: PokerSession(amount: 150, date: Date(), notes: "Good session", gameType: .cash, variant: "No Limit Hold'em", hoursPlayed: 4, stakes: "$1/$2", venue: "Bellagio"))
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
