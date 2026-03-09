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
    @State private var showingOddsCalculator = false
    @State private var shareActivityItems: [Any] = []
    @State private var fullScreenImageIndex: Int? = nil
    
    var body: some View {
        let s = currentSession
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                amountCard
                detailsSection
                if !s.imageIds.isEmpty { imagesSection }
                if !s.attachedHands.isEmpty { attachedHandsSection }
                if !s.notes.isEmpty { notesSection(s.notes) }
                if let handNotes = s.handNotes, !handNotes.isEmpty { handNotesSection(handNotes) }
            }
            .padding()
        }
        .navigationTitle(s.displayVariantAbbreviation)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(s.displayVariantAbbreviation)
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
                        showingOddsCalculator = true
                    } label: {
                        Label("Add Hand", systemImage: "percent")
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
                            sessionStore.deleteSession(s)
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
            EditSessionView(session: s)
        }
        .sheet(isPresented: $showingOddsCalculator) {
            OddsCalculatorView(preselectedSessionID: s.id)
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivitySheet(activityItems: shareActivityItems)
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenImageIndex.map { IndexWrapper(index: $0) } },
            set: { fullScreenImageIndex = $0?.index }
        )) { wrapper in
            FullScreenPhotoViewer(
                imageIds: s.imageIds,
                selectedIndex: wrapper.index,
                onDismiss: { fullScreenImageIndex = nil }
            )
        }
        .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                sessionStore.deleteSession(s)
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
    
    private var amountCard: some View {
        let s = currentSession
        return VStack(spacing: 8) {
            if settingsStore.settings.showSessionNumbers {
                Text("Session #\(sessionStore.displayNumber(for: s) ?? 0)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(formattedAmount(s.amount))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(s.isWin ? settingsStore.settings.profitLossColorScheme.winColor : settingsStore.settings.profitLossColorScheme.lossColor)
            Text(s.date, style: .date)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            if let start = s.startTime, let end = s.endTime {
                Text(timeRangeString(from: start, to: end))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
            } else if let start = s.startTime {
                Text("Started \(timeString(from: start))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
            } else if let end = s.endTime {
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
        let s = currentSession
        return VStack(alignment: .leading, spacing: 16) {
            // Game — format, variant, stakes
            detailCard(title: "Game") {
                detailRow("Format", s.gameType.abbreviation)
                detailRow("Variant", s.displayVariantAbbreviation)
                if let stakes = s.stakes, !stakes.isEmpty {
                    detailRow("Stakes", stakes)
                }
            }
            
            // Cash game stats
            if s.gameType == .cash || s.gameType == .plo || s.gameType == .homeGame || s.gameType == .online,
               s.hoursPlayed != nil || s.hourlyRate != nil {
                detailCard(title: "Session") {
                    if let hours = s.hoursPlayed {
                        detailRow("Hours Played", "\(String(format: "%.1f", hours))")
                    }
                    if let rate = s.hourlyRate {
                        detailRow("Hourly Rate", PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency) + "/hr")
                    }
                }
            }
            
            // Tournament stats
            if s.gameType == .tournament || s.gameType == .sitAndGo {
                let hasTournamentData = s.buyIn != nil || s.cashOut != nil || s.tournamentPosition != nil || (s.rebuys ?? 0) > 0 || s.tournamentROI != nil || s.hoursPlayed != nil
                if hasTournamentData {
                    detailCard(title: "Tournament") {
                        if let buyIn = s.buyIn {
                            detailRow("Buy-in", PokerSession.formatCurrency(buyIn, currency: settingsStore.settings.currency))
                        }
                        if let cashOut = s.cashOut {
                            detailRow("Cash Out", PokerSession.formatCurrency(cashOut, currency: settingsStore.settings.currency))
                        }
                        if let pos = s.tournamentPosition {
                            detailRow("Position", "\(pos)")
                        }
                        if let rebuys = s.rebuys, rebuys > 0 {
                            detailRow("Rebuys", "\(rebuys)")
                        }
                        if let roi = s.tournamentROI {
                            detailRow("ROI", String(format: "%.0f%%", roi))
                        }
                        if let hours = s.hoursPlayed {
                            detailRow("Duration", "\(String(format: "%.1f", hours)) hrs")
                        }
                    }
                }
            }
            
            // Venue
            if let venue = s.venue, !venue.isEmpty {
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
        let s = currentSession
        return VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.headline)
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 8)
            ], spacing: 8) {
                ForEach(Array(s.imageIds.enumerated()), id: \.element) { index, imageId in
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

    private var attachedHandsSection: some View {
        let s = currentSession
        return VStack(alignment: .leading, spacing: 10) {
            Text("Attached Hands")
                .font(.headline)
            ForEach(Array(s.attachedHands.enumerated()), id: \.element.id) { index, hand in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hand \(index + 1) • \(hand.game)")
                        .font(.subheadline.weight(.semibold))
                    if !hand.playerHands.isEmpty {
                        Text(hand.playerHands.joined(separator: " vs "))
                            .font(.subheadline)
                    }
                    if let board = hand.board, !board.isEmpty {
                        Text("Board: \(board)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let dead = hand.deadCards, !dead.isEmpty {
                        Text("Dead: \(dead)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(hand.resultSummary, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = hand.note, !note.isEmpty {
                        Text("Hand Note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(note)
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
            }
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

    private var currentSession: PokerSession {
        sessionStore.sessions.first(where: { $0.id == session.id }) ?? session
    }
    
    private var sessionShareText: String {
        let s = currentSession
        var lines = [
            "\(s.displayVariantAbbreviation) \(s.gameType.abbreviation) • \(formattedAmount(s.amount))",
            s.date.formatted(date: .long, time: .omitted)
        ]
        if let stakes = s.stakes, !stakes.isEmpty { lines.append("Stakes: \(stakes)") }
        if let venue = s.venue, !venue.isEmpty { lines.append("Venue: \(venue)") }
        if let start = s.startTime, let end = s.endTime {
            lines.append("\(timeString(from: start)) – \(timeString(from: end))")
        }
        if let hours = s.hoursPlayed { lines.append("Hours: \(String(format: "%.1f", hours))") }
        if let roi = s.tournamentROI { lines.append("ROI: \(String(format: "%.0f%%", roi))") }
        if !s.notes.isEmpty { lines.append("Notes: \(s.notes)") }
        if let handNotes = s.handNotes, !handNotes.isEmpty { lines.append("Hand Notes: \(handNotes)") }
        if !s.attachedHands.isEmpty {
            lines.append("Attached Hands: \(s.attachedHands.count)")
            for (index, hand) in s.attachedHands.enumerated() {
                lines.append("Hand \(index + 1): \(hand.playerHands.joined(separator: " vs "))")
                if !hand.resultSummary.isEmpty {
                    lines.append(contentsOf: hand.resultSummary)
                }
                if let note = hand.note, !note.isEmpty {
                    lines.append("Hand Note: \(note)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
    
    private var sessionShareItems: [Any] {
        let images = currentSession.imageIds.compactMap { SessionImageStore.loadImage(imageId: $0) }
        return [sessionShareText] + images
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
