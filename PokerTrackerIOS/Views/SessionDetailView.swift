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
    @State private var showingOddsCalculator = false
    @State private var fullScreenImageIndex: Int? = nil
    
    var body: some View {
        let s = currentSession
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                amountCard
                detailsSection
                if !s.tags.isEmpty { tagsSection }
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
                        presentShareSheet(items: sessionShareItems)
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
    
    private var resultColor: Color {
        let s = currentSession
        return s.isWin ? settingsStore.settings.profitLossColorScheme.winColor : settingsStore.settings.profitLossColorScheme.lossColor
    }

    private var amountCard: some View {
        let s = currentSession
        return VStack(spacing: 10) {
            if settingsStore.settings.showSessionNumbers {
                Text("SESSION #\(sessionStore.displayNumber(for: s) ?? 0)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
            }
            Text(formattedAmount(s.amount))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(resultColor)
                .contentTransition(.numericText())
            Text(s.date, style: .date)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if let start = s.startTime, let end = s.endTime {
                Text(timeRangeString(from: start, to: end))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if let start = s.startTime {
                Text("Started \(timeString(from: start))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if let end = s.endTime {
                Text("Ended \(timeString(from: end))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: resultColor.opacity(0.12), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(resultColor.opacity(0.15), lineWidth: 1)
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
    
    private var tagsSection: some View {
        let s = currentSession
        return VStack(alignment: .leading, spacing: 10) {
            Text("TAGS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            FlowLayout(spacing: 6) {
                ForEach(s.tags, id: \.self) { tag in
                    if let t = SessionTag(rawValue: tag) {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.caption2)
                            Text(t.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(t.color.opacity(0.12))
                        .foregroundStyle(t.color)
                        .clipShape(Capsule())
                    } else {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            
            VStack(spacing: 10) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            Text(notes)
                .font(.body)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
    }
    
    private func handNotesSection(_ handNotes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HAND NOTES")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            Text(handNotes)
                .font(.body)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
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
        if !s.tags.isEmpty { lines.append("Tags: \(s.tags.joined(separator: ", "))") }
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

    private func presentShareSheet(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = vc.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: 0, width: 0, height: 0)
            popover.permittedArrowDirections = .up
        }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(vc, animated: true)
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

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentY += rowHeight + spacing
                currentX = 0
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentY += rowHeight + spacing
                currentX = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
