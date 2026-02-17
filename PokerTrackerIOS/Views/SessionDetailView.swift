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
        .navigationTitle(session.displayVariantAbbreviation)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.displayVariantAbbreviation)
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
            if let start = session.startTime, let end = session.endTime {
                Text(timeRangeString(from: start, to: end))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
            } else if let start = session.startTime {
                Text("Started \(timeString(from: start))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
            } else if let end = session.endTime {
                Text("Ended \(timeString(from: end))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.cardBackground)
        )
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Game — format, variant, stakes
            detailCard(title: "Game") {
                detailRow("Format", session.gameType.abbreviation)
                detailRow("Variant", session.displayVariantAbbreviation)
                if let stakes = session.stakes, !stakes.isEmpty {
                    detailRow("Stakes", stakes)
                }
            }
            
            // Cash game stats
            if session.gameType == .cash || session.gameType == .plo || session.gameType == .homeGame || session.gameType == .online,
               session.hoursPlayed != nil || session.hourlyRate != nil {
                detailCard(title: "Session") {
                    if let hours = session.hoursPlayed {
                        detailRow("Hours Played", "\(String(format: "%.1f", hours))")
                    }
                    if let rate = session.hourlyRate {
                        detailRow("Hourly Rate", PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency) + "/hr")
                    }
                }
            }
            
            // Tournament stats
            if session.gameType == .tournament || session.gameType == .sitAndGo {
                let hasTournamentData = session.buyIn != nil || session.cashOut != nil || session.tournamentPosition != nil || (session.rebuys ?? 0) > 0 || session.tournamentROI != nil || session.hoursPlayed != nil
                if hasTournamentData {
                    detailCard(title: "Tournament") {
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
                        if let hours = session.hoursPlayed {
                            detailRow("Duration", "\(String(format: "%.1f", hours)) hrs")
                        }
                    }
                }
            }
            
            // Venue
            if let venue = session.venue, !venue.isEmpty {
                detailCard(title: "Location") {
                    detailRow("Venue", venue)
                }
            }
        }
    }
    
    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            VStack(spacing: 8) {
                content()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            )
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
    
    private func timeString(from date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
    
    private func timeRangeString(from start: Date, to end: Date) -> String {
        "\(timeString(from: start)) – \(timeString(from: end))"
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
            "\(session.displayVariantAbbreviation) \(session.gameType.abbreviation) • \(PokerSession.formatCurrency(session.amount, currency: settingsStore.settings.currency))",
            session.date.formatted(date: .long, time: .omitted)
        ]
        if let stakes = session.stakes, !stakes.isEmpty { lines.append("Stakes: \(stakes)") }
        if let venue = session.venue, !venue.isEmpty { lines.append("Venue: \(venue)") }
        if let start = session.startTime, let end = session.endTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            lines.append("\(formatter.string(from: start)) – \(formatter.string(from: end))")
        }
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
