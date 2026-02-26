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
    @State private var showingShareSheet = false
    @State private var shareActivityItems: [Any] = []
    @State private var fullScreenImageIndex: Int? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                amountCard
                detailsSection
                if !session.imageIds.isEmpty { imagesSection }
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
                    Button {
                        shareActivityItems = sessionShareItems
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        if settingsStore.settings.confirmBeforeDelete {
                            showingDeleteConfirm = true
                        } else {
                            sessionStore.deleteSession(session)
                            dismiss()
                        }
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
        .sheet(isPresented: $showingShareSheet) {
            ActivitySheet(activityItems: shareActivityItems)
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenImageIndex.map { IndexWrapper(index: $0) } },
            set: { fullScreenImageIndex = $0?.index }
        )) { wrapper in
            FullScreenPhotoViewer(
                imageIds: session.imageIds,
                selectedIndex: wrapper.index,
                onDismiss: { fullScreenImageIndex = nil }
            )
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
            if settingsStore.settings.showSessionNumbers {
                Text("Session #\(sessionStore.displayNumber(for: session) ?? 0)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(formattedAmount(session.amount))
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
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        if settingsStore.settings.use24HourTime {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
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
    
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.headline)
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 8)
            ], spacing: 8) {
                ForEach(Array(session.imageIds.enumerated()), id: \.element) { index, imageId in
                    SessionImageView(imageId: imageId)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(minHeight: 100)
                        .clipped()
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            fullScreenImageIndex = index
                        }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        )
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
    
    private struct IndexWrapper: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private func formattedAmount(_ value: Double) -> String {
        let currency = settingsStore.settings.currency
        if settingsStore.settings.useCompactCurrency {
            let prefix = value > 0 ? "+" : (value < 0 ? "-" : "")
            return prefix + PokerSession.formatCompactCurrency(abs(value), currency: currency)
        }
        return PokerSession.formatCurrency(value, currency: currency)
    }
    
    private var sessionShareText: String {
        var lines = [
            "\(session.displayVariantAbbreviation) \(session.gameType.abbreviation) • \(formattedAmount(session.amount))",
            session.date.formatted(date: .long, time: .omitted)
        ]
        if let stakes = session.stakes, !stakes.isEmpty { lines.append("Stakes: \(stakes)") }
        if let venue = session.venue, !venue.isEmpty { lines.append("Venue: \(venue)") }
        if let start = session.startTime, let end = session.endTime {
            lines.append("\(timeString(from: start)) – \(timeString(from: end))")
        }
        if let hours = session.hoursPlayed { lines.append("Hours: \(String(format: "%.1f", hours))") }
        if let roi = session.tournamentROI { lines.append("ROI: \(String(format: "%.0f%%", roi))") }
        if !session.notes.isEmpty { lines.append("Notes: \(session.notes)") }
        if let handNotes = session.handNotes, !handNotes.isEmpty { lines.append("Hand Notes: \(handNotes)") }
        return lines.joined(separator: "\n")
    }
    
    /// Text summary for sharing (no images)
    private var sessionShareItems: [Any] {
        [sessionShareText]
    }
}

// MARK: - Full Screen Photo Viewer

struct FullScreenPhotoViewer: View {
    let imageIds: [String]
    let selectedIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    
    init(imageIds: [String], selectedIndex: Int, onDismiss: @escaping () -> Void) {
        self.imageIds = imageIds
        self.selectedIndex = selectedIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: selectedIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(imageIds.enumerated()), id: \.element) { index, imageId in
                    SessionImageView(imageId: imageId)
                        .aspectRatio(contentMode: .fit)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: imageIds.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: PokerSession(amount: 150, date: Date(), notes: "Good session", gameType: .cash, variant: "No Limit Hold'em", hoursPlayed: 4, stakes: "$1/$2", venue: "Bellagio"))
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
