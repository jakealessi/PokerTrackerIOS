//
//  OddsCalculatorView.swift
//  PokerTrackerIOS
//
//  Exact-equity odds calculator for NLH and PLO. Up to 6 hands, multiple boards, dead cards.
//  15 free uses total (charged once per hand on flop+), then Premium.
//

import SwiftUI

struct OddsCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let preselectedSessionID: UUID?
    let onHandCreated: ((PokerSession.AttachedHand) -> Void)?
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var showingAttachSheet = false
    @State private var showingAddSession = false
    @State private var gameType: EquityGameType = .nlh
    @State private var numberOfHands = 2
    @State private var hands: [[PlayingCard]] = Array(repeating: [], count: 6)
    @State private var numberOfBoards = 1
    @State private var boards: [[PlayingCard]] = Array(repeating: [], count: 4)
    @State private var deadCards: [PlayingCard] = []
    @State private var selectedSlot: SlotTarget? = .hand(0, 0)
    @State private var result: EquityResult?
    @State private var boardResults: [BoardEquityResult] = []
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var lastChargedCalculationSignature: String?
    @State private var pendingAttachedHandForNewSession: PokerSession.AttachedHand?
    @State private var showingQuickAttachNote = false
    @State private var quickAttachNote = ""
    @State private var calculationTask: Task<Void, Never>?

    private var isFromSession: Bool { preselectedSessionID != nil }

    init(
        preselectedSessionID: UUID? = nil,
        onHandCreated: ((PokerSession.AttachedHand) -> Void)? = nil
    ) {
        self.preselectedSessionID = preselectedSessionID
        self.onHandCreated = onHandCreated
    }

    private var canUse: Bool {
        subscriptionStore.isSubscribed || OddsCalculatorUsage.hasFreeUsesRemaining
    }

    private var canAccessCalculator: Bool {
        canUse || result != nil || isCalculating
    }

    private var premiumCTAButtonTitle: String {
        if subscriptionStore.proMonthlyProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Unlock Premium — Start Free Trial"
        }
        return "Unlock Premium"
    }

    var body: some View {
        NavigationStack {
            Group {
                if canAccessCalculator {
                    calculatorContent
                } else {
                    paywallSection
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Odds Calculator")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .primaryAction) {
                    if isFromSession {
                        Button {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            quickAttachNote = ""
                            showingQuickAttachNote = true
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(AppTheme.accent)
                        .disabled(result == nil)
                    } else {
                        ShareLink(item: handShareText) {
                            Text("Share")
                                .font(.subheadline)
                                .foregroundStyle(hasShareableHand ? AppTheme.accent : Color.gray)
                        }
                        .disabled(!hasShareableHand)
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAttachSheet, onDismiss: handleAttachSheetDismiss) {
                if let attachedHandDraft = makeAttachedHand(note: nil) {
                    AttachHandToSessionSheet(
                        handDraft: attachedHandDraft,
                        preselectedSessionID: preselectedSessionID
                    ) { handForNewSession in
                        pendingAttachedHandForNewSession = handForNewSession
                    }
                    .environmentObject(sessionStore)
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showingAddSession, onDismiss: {
                pendingAttachedHandForNewSession = nil
            }) {
                AddSessionView(
                    prefilledAttachedHands: pendingAttachedHandForNewSession.map { [$0] } ?? []
                )
                .presentationDetents([.medium, .large])
            }
            .alert("Add Hand Note", isPresented: $showingQuickAttachNote) {
                TextField("Optional note", text: $quickAttachNote)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    if let sessionID = preselectedSessionID,
                       let hand = makeAttachedHand(note: quickAttachNote) {
                        sessionStore.addAttachedHand(hand, toSessionID: sessionID)
                    } else if let onHandCreated,
                              let hand = makeAttachedHand(note: quickAttachNote) {
                        onHandCreated(hand)
                        dismiss()
                    }
                }
            } message: {
                Text("Add an optional note for this hand, then tap Save to attach it to your session.")
            }
            .onDisappear {
                calculationTask?.cancel()
            }
        }
    }

    private var paywallSection: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "percent")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent.opacity(0.6))
            Text("Odds Calculator")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Calculate exact win and tie percentages for NLH, PLO, and 5-Card PLO. 15 free uses total (charged once per hand on flop+), then unlock unlimited with Premium.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                showingPaywall = true
            } label: {
                Text(premiumCTAButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent)
                    .foregroundStyle(.white)
                    .cornerRadius(AppTheme.smallCornerRadius)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var calculatorContent: some View {
        GeometryReader { geo in
            let cols = 13
            let rows = 4
            let spacing: CGFloat = 2
            let horizontalPadding: CGFloat = 8
            let availableW = geo.size.width - horizontalPadding - spacing * CGFloat(cols - 1)
            let cardW = max(24, availableW / CGFloat(cols))
            let cardH = cardW * 1.4
            let cardGridHeight = CGFloat(rows) * cardH + CGFloat(rows - 1) * spacing + 12

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !subscriptionStore.isSubscribed {
                            usageBanner
                        }
                        gameTypePicker
                        actionsRow
                        handsSection
                        boardSection
                        if let r = result, !isCalculating {
                            resultsSection(r)
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))

                cardGrid
                    .frame(height: cardGridHeight)
            }
            .overlay {
                if isCalculating {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Calculating odds…")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    private var usageBanner: some View {
        HStack {
            Text("\(OddsCalculatorUsage.usesRemaining) of \(OddsCalculatorUsage.freeUseLimit) free uses left")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if OddsCalculatorUsage.usesRemaining == 0 {
                Button("Unlock unlimited") {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    showingPaywall = true
                }
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.smallCornerRadius)
    }

    private var gameTypePicker: some View {
        Picker("Game", selection: $gameType) {
            Text("NLH").tag(EquityGameType.nlh)
            Text("PLO").tag(EquityGameType.plo)
            Text("PLO-5").tag(EquityGameType.plo5)
        }
        .pickerStyle(.segmented)
        .onChange(of: gameType) { _, _ in
            clearAll()
        }
    }

    private var handsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hands")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(0..<numberOfHands, id: \.self) { i in
                handRow(index: i)
            }
            if numberOfHands < 6 {
                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    numberOfHands += 1
                } label: {
                    Label("Add Hand", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            if numberOfHands > 2 {
                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    removeLastHand()
                } label: {
                    Label("Remove Hand", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsRow: some View {
        HStack {
            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            Spacer()
        }
    }

    private func handRow(index: Int) -> some View {
        let needed = gameType.cardsPerHand
        let cards = hands[index]
        return HStack(spacing: 4) {
            Text("Hand \(index + 1)")
                .font(.caption)
                .frame(width: 50, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<needed, id: \.self) { j in
                    cardSlot(
                        card: cards.indices.contains(j) ? cards[j] : nil,
                        isSelected: selectedSlot == .hand(index, j),
                        selectAction: { selectedSlot = .hand(index, j) }
                    )
                }
            }
            if let r = result, let resultIdx = activeHandIndices.firstIndex(of: index) {
                Text(String(format: "Win: %.1f%%  Tie: %.1f%%", r.winPercent(forHand: resultIdx), r.tiePercent(forHand: resultIdx)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(selectedSlot?.handIndex == index ? AppTheme.accent.opacity(0.15) : Color.clear)
        .cornerRadius(8)
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(numberOfBoards == 1 ? "Board" : "Boards")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if numberOfBoards < boards.count {
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        addBoard()
                    } label: {
                        Label("Add Board", systemImage: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            ForEach(0..<numberOfBoards, id: \.self) { boardIndex in
                HStack(spacing: 4) {
                    if numberOfBoards > 1 {
                        Text("Board \(boardIndex + 1)")
                            .font(.caption)
                            .frame(width: 56, alignment: .leading)
                    }
                    ForEach(0..<5, id: \.self) { cardIndex in
                        cardSlot(
                            card: boards[boardIndex].indices.contains(cardIndex) ? boards[boardIndex][cardIndex] : nil,
                            isSelected: selectedSlot == .board(boardIndex, cardIndex),
                            selectAction: { selectedSlot = .board(boardIndex, cardIndex) }
                        )
                    }
                    if numberOfBoards > 1, boardIndex == numberOfBoards - 1 {
                        Button {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            removeLastBoard()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove Board")
                    }
                }
            }
            Text("Dead Cards")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { i in
                        cardSlot(
                            card: deadCards.indices.contains(i) ? deadCards[i] : nil,
                            isSelected: selectedSlot == .dead(i),
                            selectAction: { selectedSlot = .dead(i) }
                        )
                    }
                }
            }
        }
    }

    private func cardSlot(card: PlayingCard?, isSelected: Bool, selectAction: @escaping () -> Void) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(card.map { suitColor(for: $0) } ?? Color(UIColor.tertiarySystemFill))
                .frame(width: 40, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2)
                )
            if let c = card {
                Text(cardDisplay(c))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 48, minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
            if let card {
                removeCard(card)
            } else {
                selectAction()
            }
        }
    }

    private var cardGridDisplayOrder: [PlayingCard] {
        let aceFirstRanks: [PlayingCard.Rank] = [.ace, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king]
        return PlayingCard.Suit.allCases.flatMap { suit in
            aceFirstRanks.map { PlayingCard(rank: $0, suit: suit) }
        }
    }

    private var cardGrid: some View {
        GeometryReader { geo in
                let cols = 13
                let rows = 4
                let spacing: CGFloat = 2
                let availableW = geo.size.width - spacing * CGFloat(cols - 1)
                let availableH = geo.size.height - spacing * CGFloat(rows - 1)
                let cardWFromWidth = availableW / CGFloat(cols)
                let cardHFromHeight = availableH / CGFloat(rows)
                let cardW = max(24, min(cardWFromWidth, cardHFromHeight / 1.4))
                let cardH = cardW * 1.4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols), spacing: spacing) {
                    ForEach(cardGridDisplayOrder, id: \.self) { card in
                        if isCardUsed(card) {
                            Text(cardDisplay(card))
                                .font(.system(size: max(10, min(14, cardW * 0.5)), weight: .medium))
                                .frame(width: cardW, height: cardH)
                                .background(Color(UIColor.tertiarySystemFill))
                                .cornerRadius(6)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                addCard(card)
                            } label: {
                                Text(cardDisplay(card))
                                    .font(.system(size: max(10, min(14, cardW * 0.5)), weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: cardW, height: cardH)
                                    .background(suitColor(for: card))
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var activeHandIndices: [Int] {
        let needed = gameType.cardsPerHand
        return (0..<numberOfHands).filter { hands[$0].count == needed }
    }

    private var activeBoards: [[PlayingCard]] {
        Array(boards.prefix(numberOfBoards))
    }

    private var boardsForCalculation: [(index: Int, cards: [PlayingCard])] {
        let enteredBoards = activeBoards.enumerated().filter { !$0.element.isEmpty }
        if enteredBoards.isEmpty {
            return [(0, [])]
        }
        return enteredBoards.map { ($0.offset, $0.element) }
    }

    private var hasShareableHand: Bool {
        hands.contains(where: { !$0.isEmpty }) || activeBoards.contains(where: { !$0.isEmpty }) || !deadCards.isEmpty
    }

    private var canCalculate: Bool {
        let needed = gameType.cardsPerHand
        let activeHands = hands.filter { $0.count == needed }
        guard activeHands.count >= 2 else { return false }
        let allCards = hands.flatMap { $0 } + activeBoards.flatMap { $0 } + deadCards
        return Set(allCards).count == allCards.count
    }

    private var boardValidationMessage: String? {
        let boardCounts = boardsForCalculation.map { $0.cards.count }
        if boardCounts.contains(where: { $0 > 0 && $0 < 3 }) {
            return "Board needs at least 3 cards (complete flop) to calculate."
        }
        guard boardCounts.allSatisfy({ $0 == 0 || [3, 4, 5].contains($0) }) else { return nil }
        guard boardCounts.count > 1, Set(boardCounts).count > 1 else { return nil }
        return "Multiple boards must be on the same street."
    }

    private func resultsSection(_ r: EquityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results (\(r.totalRunouts) runouts)")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(activeHandIndices, id: \.self) { handIdx in
                if let resultIdx = activeHandIndices.firstIndex(of: handIdx) {
                    HStack {
                        Text("Hand \(handIdx + 1):")
                        Spacer()
                        Text(String(format: "Win: %.1f%%  Tie: %.1f%%", r.winPercent(forHand: resultIdx), r.tiePercent(forHand: resultIdx)))
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
            }
            if boardResults.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("By board")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(boardResults) { boardResult in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Board \(boardResult.boardIndex + 1): \(handString(boardResult.board))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(activeHandIndices, id: \.self) { handIdx in
                                if let resultIdx = activeHandIndices.firstIndex(of: handIdx) {
                                    HStack {
                                        Text("Hand \(handIdx + 1)")
                                        Spacer()
                                        Text(String(format: "%.1f%% / %.1f%%", boardResult.result.winPercent(forHand: resultIdx), boardResult.result.tiePercent(forHand: resultIdx)))
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            if !isFromSession {
                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    if onHandCreated != nil {
                        quickAttachNote = ""
                        showingQuickAttachNote = true
                    } else {
                        showingAttachSheet = true
                    }
                } label: {
                    Label(onHandCreated != nil ? "Add Hand" : "Add to Session", systemImage: "plus.bubble")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .padding(.top, 6)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.smallCornerRadius)
    }

    // MARK: - Slot Target

    enum SlotTarget: Equatable {
        case hand(Int, Int)
        case board(Int, Int)
        case dead(Int)
        var handIndex: Int? {
            if case .hand(let i, _) = self { return i }
            return nil
        }
    }

    private struct BoardEquityResult: Identifiable {
        let boardIndex: Int
        let board: [PlayingCard]
        let result: EquityResult

        var id: Int { boardIndex }
    }

    // MARK: - Helpers

    private func suitColor(for card: PlayingCard) -> Color {
        let base: Color
        switch card.suit {
        case .hearts:   base = .red
        case .spades:   base = colorScheme == .dark ? Color(white: 0.28) : .black
        case .clubs:    base = .green
        case .diamonds: base = .blue
        }
        return base.opacity(0.78)
    }

    private func cardDisplay(_ c: PlayingCard) -> String {
        let r: String
        switch c.rank.rawValue {
        case 14: r = "A"
        case 13: r = "K"
        case 12: r = "Q"
        case 11: r = "J"
        case 10: r = "T"
        default: r = "\(c.rank.rawValue)"
        }
        return r + c.suit.rawValue
    }

    private func isCardUsed(_ card: PlayingCard) -> Bool {
        hands.flatMap { $0 }.contains(card) || activeBoards.flatMap { $0 }.contains(card) || deadCards.contains(card)
    }

    private func handString(_ cards: [PlayingCard]) -> String {
        cards.map(cardDisplay).joined(separator: " ")
    }

    private var gameLabel: String {
        switch gameType {
        case .nlh: return "No Limit Hold'em"
        case .plo: return "Pot Limit Omaha"
        case .plo5: return "5-Card PLO"
        }
    }

    private func makeAttachedHand(note: String?) -> PokerSession.AttachedHand? {
        guard let currentResult = result else { return nil }
        let playerHandStrings = activeHandIndices.map { handString(hands[$0]) }
        guard playerHandStrings.count >= 2 else { return nil }

        let summaries = activeHandIndices.compactMap { handIndex -> String? in
            guard let resultIndex = activeHandIndices.firstIndex(of: handIndex) else { return nil }
            return String(
                format: "Hand %d: Win %.1f%% • Tie %.1f%%",
                handIndex + 1,
                currentResult.winPercent(forHand: resultIndex),
                currentResult.tiePercent(forHand: resultIndex)
            )
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PokerSession.AttachedHand(
            game: gameLabel,
            playerHands: playerHandStrings,
            board: boardSummaryText,
            deadCards: deadCards.isEmpty ? nil : handString(deadCards),
            resultSummary: summaries,
            note: (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        )
    }

    private var handShareText: String {
        var lines: [String] = ["Odds Calculator • \(gameLabel)"]

        for handIndex in 0..<numberOfHands where !hands[handIndex].isEmpty {
            lines.append("Hand \(handIndex + 1): \(handString(hands[handIndex]))")
        }

        for (index, board) in activeBoards.enumerated() where !board.isEmpty {
            lines.append("\(numberOfBoards == 1 ? "Board" : "Board \(index + 1)"): \(handString(board))")
        }
        if !deadCards.isEmpty {
            lines.append("Dead: \(handString(deadCards))")
        }

        if let currentResult = result {
            lines.append("Results (\(currentResult.totalRunouts) runouts)")
            for handIdx in activeHandIndices {
                if let resultIdx = activeHandIndices.firstIndex(of: handIdx) {
                    lines.append(
                        String(
                            format: "Hand %d: Win %.1f%% • Tie %.1f%%",
                            handIdx + 1,
                            currentResult.winPercent(forHand: resultIdx),
                            currentResult.tiePercent(forHand: resultIdx)
                        )
                    )
                }
            }
        } else {
            lines.append("Results: Not calculated yet")
        }

        return lines.joined(separator: "\n")
    }

    private var boardSummaryText: String? {
        let populatedBoards = activeBoards.enumerated().filter { !$0.element.isEmpty }
        guard !populatedBoards.isEmpty else { return nil }
        if populatedBoards.count == 1, numberOfBoards == 1 {
            return handString(populatedBoards[0].element)
        }
        return populatedBoards
            .map { "Board \($0.offset + 1): \(handString($0.element))" }
            .joined(separator: "\n")
    }

    private func handleAttachSheetDismiss() {
        guard pendingAttachedHandForNewSession != nil else { return }
        showingAddSession = true
    }

    private func addCard(_ card: PlayingCard) {
        guard let slot = selectedSlot, !isCardUsed(card) else { return }
        var didPlace = false
        switch slot {
        case .hand(let hi, let ci):
            guard hi < numberOfHands else { return }
            if ci >= hands[hi].count, hands[hi].count < gameType.cardsPerHand {
                var updatedHands = hands
                updatedHands[hi] = hands[hi] + [card]
                hands = updatedHands
                didPlace = true
            } else if hands[hi].indices.contains(ci) {
                var updatedHands = hands
                var handCopy = updatedHands[hi]
                handCopy[ci] = card
                updatedHands[hi] = handCopy
                hands = updatedHands
                didPlace = true
            }
        case .board(let boardIndex, let cardIndex):
            guard boardIndex < numberOfBoards else { return }
            if cardIndex >= boards[boardIndex].count, boards[boardIndex].count < 5 {
                var updatedBoards = boards
                updatedBoards[boardIndex] = boards[boardIndex] + [card]
                boards = updatedBoards
                didPlace = true
            } else if boards[boardIndex].indices.contains(cardIndex) {
                var updatedBoards = boards
                var boardCopy = updatedBoards[boardIndex]
                boardCopy[cardIndex] = card
                updatedBoards[boardIndex] = boardCopy
                boards = updatedBoards
                didPlace = true
            }
        case .dead(let i):
            if i >= deadCards.count, deadCards.count < 10 {
                deadCards = deadCards + [card]
                didPlace = true
            } else if deadCards.indices.contains(i) {
                var updated = deadCards
                updated[i] = card
                deadCards = updated
                didPlace = true
            }
        }
        if didPlace {
            advanceSelection(after: slot)
            triggerCalculationIfNeeded()
        }
    }

    private func removeLastHand() {
        guard numberOfHands > 2 else { return }
        let idx = numberOfHands - 1
        var updated = hands
        updated[idx] = []
        hands = updated
        numberOfHands -= 1
        if let h = selectedSlot?.handIndex, h >= numberOfHands {
            selectedSlot = .hand(max(0, numberOfHands - 1), 0)
        }
        triggerCalculationIfNeeded()
    }

    private func addBoard() {
        guard numberOfBoards < boards.count else { return }
        numberOfBoards += 1
        selectedSlot = .board(numberOfBoards - 1, 0)
        triggerCalculationIfNeeded()
    }

    private func removeLastBoard() {
        guard numberOfBoards > 1 else { return }
        let idx = numberOfBoards - 1
        var updated = boards
        updated[idx] = []
        boards = updated
        numberOfBoards -= 1
        if case .board(let selectedBoardIndex, _) = selectedSlot, selectedBoardIndex >= numberOfBoards {
            selectedSlot = .board(max(0, numberOfBoards - 1), 0)
        }
        triggerCalculationIfNeeded()
    }

    private func removeCard(_ card: PlayingCard) {
        let needed = gameType.cardsPerHand
        for i in 0..<hands.count {
            if let idx = hands[i].firstIndex(of: card) {
                var updatedHands = hands
                var handCopy = updatedHands[i]
                handCopy.remove(at: idx)
                updatedHands[i] = handCopy
                hands = updatedHands
                let nextEmptyIndex = min(handCopy.count, max(0, needed - 1))
                selectedSlot = .hand(i, nextEmptyIndex)
                triggerCalculationIfNeeded()
                return
            }
        }
        for boardIndex in 0..<numberOfBoards {
            if let idx = boards[boardIndex].firstIndex(of: card) {
                var updatedBoards = boards
                var boardCopy = updatedBoards[boardIndex]
                boardCopy.remove(at: idx)
                updatedBoards[boardIndex] = boardCopy
                boards = updatedBoards
                selectedSlot = .board(boardIndex, min(boardCopy.count, 4))
                triggerCalculationIfNeeded()
                return
            }
        }
        if let idx = deadCards.firstIndex(of: card) {
            var updated = deadCards
            updated.remove(at: idx)
            deadCards = updated
            selectedSlot = .dead(min(updated.count, 9))
            triggerCalculationIfNeeded()
            return
        }
    }

    private func triggerCalculationIfNeeded() {
        guard canUse else { return }
        let calculationBoards = boardsForCalculation
        let boardCounts = calculationBoards.map { $0.cards.count }
        if let boardValidationMessage {
            calculationTask?.cancel()
            isCalculating = false
            result = nil
            boardResults = []
            errorMessage = boardValidationMessage
        } else if boardCounts.allSatisfy({ [0, 3, 4, 5].contains($0) }), canCalculate {
            runCalculation()
        } else {
            calculationTask?.cancel()
            isCalculating = false
            result = nil
            boardResults = []
            errorMessage = nil
            // When board is incomplete, treat next completed solve as a new chargeable hand.
            if boardCounts.contains(where: { $0 < 3 }) {
                lastChargedCalculationSignature = nil
            }
        }

        // Full reset if user manually clears all cards.
        if hands.allSatisfy({ $0.isEmpty }) && activeBoards.allSatisfy({ $0.isEmpty }) && deadCards.isEmpty {
            lastChargedCalculationSignature = nil
        }
    }

    private func advanceSelection(after slot: SlotTarget) {
        switch slot {
        case .hand(let handIndex, let cardIndex):
            let needed = gameType.cardsPerHand
            if cardIndex + 1 < needed {
                // Next card in the same hand
                selectedSlot = .hand(handIndex, cardIndex + 1)
            } else {
                // Move to first card of next hand if there is one
                let nextHand = handIndex + 1
                if nextHand < numberOfHands {
                    selectedSlot = .hand(nextHand, 0)
                } else {
                    // After last hand, move to the board (never auto-into dead cards)
                    selectedSlot = .board(0, 0)
                }
            }
        case .board(let boardIndex, let cardIndex):
            let nextCard = cardIndex + 1
            if nextCard < 5 {
                selectedSlot = .board(boardIndex, nextCard)
            } else {
                // Stay on last board slot; do not auto-advance into dead cards.
                selectedSlot = .board(boardIndex, cardIndex)
            }
        case .dead(let deadIndex):
            // If user is in dead cards, advance within dead cards only
            let nextDead = deadIndex + 1
            if nextDead < 10 {
                selectedSlot = .dead(nextDead)
            } else {
                selectedSlot = .dead(deadIndex)
            }
        }
    }

    private func clearAll() {
        calculationTask?.cancel()
        numberOfHands = 2
        hands = Array(repeating: [], count: 6)
        numberOfBoards = 1
        boards = Array(repeating: [], count: 4)
        deadCards = []
        result = nil
        boardResults = []
        errorMessage = nil
        isCalculating = false
        lastChargedCalculationSignature = nil
        selectedSlot = .hand(0, 0)
    }

    private func runCalculation() {
        guard canUse else {
            showingPaywall = true
            return
        }
        isCalculating = true
        errorMessage = nil
        result = nil
        boardResults = []

        let needed = gameType.cardsPerHand
        let activeHands = hands.filter { $0.count == needed }
        guard activeHands.count >= 2 else {
            errorMessage = "Need at least 2 complete hands."
            isCalculating = false
            return
        }

        let calculationGameType = gameType
        let calculationBoards = boardsForCalculation
        let cardsFromIncompleteHands = hands.filter { $0.count > 0 && $0.count != needed }.flatMap { $0 }
        let effectiveDeadCards = deadCards + cardsFromIncompleteHands
        let shouldChargeUsage = calculationBoards.contains { $0.cards.count >= 3 }
        let isSubscribed = subscriptionStore.isSubscribed
        let calculationSignature = makeCalculationSignature(
            gameType: calculationGameType,
            hands: activeHands,
            boards: calculationBoards.map { $0.cards },
            deadCards: effectiveDeadCards
        )

        calculationTask?.cancel()
        calculationTask = Task(priority: .userInitiated) {
            var perBoardResults: [BoardEquityResult] = []
            for calculationBoard in calculationBoards {
                guard !Task.isCancelled else { return }
                let otherBoardCards = calculationBoards
                    .filter { $0.index != calculationBoard.index }
                    .flatMap { $0.cards }
                let boardSpecificDeadCards = effectiveDeadCards + otherBoardCards
                let engine = PokerEquityEngine(
                    gameType: calculationGameType,
                    hands: activeHands,
                    board: calculationBoard.cards,
                    deadCards: boardSpecificDeadCards
                )
                guard let boardResult = engine.calculate() else {
                    await MainActor.run {
                        isCalculating = false
                        errorMessage = "Could not calculate. Check for duplicate cards."
                    }
                    return
                }
                perBoardResults.append(
                    BoardEquityResult(
                        boardIndex: calculationBoard.index,
                        board: calculationBoard.cards,
                        result: boardResult
                    )
                )
            }
            let res = aggregateResults(perBoardResults.map { $0.result })
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                isCalculating = false
                if let r = res {
                    result = r
                    boardResults = perBoardResults
                    if !isSubscribed,
                       shouldChargeUsage,
                       lastChargedCalculationSignature != calculationSignature {
                        OddsCalculatorUsage.consumeOne()
                        lastChargedCalculationSignature = calculationSignature
                    }
                } else {
                    errorMessage = "Could not calculate. Check for duplicate cards."
                }
            }
        }
    }

    private func makeCalculationSignature(
        gameType: EquityGameType,
        hands: [[PlayingCard]],
        boards: [[PlayingCard]],
        deadCards: [PlayingCard]
    ) -> String {
        let handText = hands.map(handString).joined(separator: "|")
        let boardText = boards.map(handString).joined(separator: "|")
        let deadText = handString(deadCards)
        return "\(gameType.cardsPerHand)#\(handText)#\(boardText)#\(deadText)"
    }

    private func aggregateResults(_ results: [EquityResult]) -> EquityResult? {
        guard let first = results.first else { return nil }
        var wins = Array(repeating: 0, count: first.wins.count)
        var ties = Array(repeating: 0.0, count: first.ties.count)
        var totalRunouts = 0

        for result in results {
            guard result.wins.count == wins.count, result.ties.count == ties.count else { return nil }
            totalRunouts += result.totalRunouts
            for index in wins.indices {
                wins[index] += result.wins[index]
                ties[index] += result.ties[index]
            }
        }

        return EquityResult(wins: wins, ties: ties, totalRunouts: totalRunouts)
    }
}

private struct AttachHandToSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    let handDraft: PokerSession.AttachedHand
    let preselectedSessionID: UUID?
    let onAttachToNewSession: (PokerSession.AttachedHand) -> Void
    @State private var note: String = ""

    private var sessionsMostRecentFirst: [PokerSession] {
        sessionStore.sessions.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    private var handToAttach: PokerSession.AttachedHand {
        var updated = handDraft
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = trimmedNote.isEmpty ? nil : trimmedNote
        return updated
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Hand Note") {
                    TextField("Optional note for this hand", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        onAttachToNewSession(handToAttach)
                        dismiss()
                    } label: {
                        Label("Attach to New Session", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }

                Section("Attach to Existing Session") {
                    if sessionsMostRecentFirst.isEmpty {
                        Text("No sessions yet. Create a new session first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessionsMostRecentFirst) { session in
                            Button {
                                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                sessionStore.addAttachedHand(handToAttach, toSessionID: session.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.displayVariantAbbreviation)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(session.date, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(PokerSession.formatCurrency(session.displayProfit(deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsStore.settings.deductExpensesFromProfit)), currency: settingsStore.settings.currency))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            session.isWinForDisplay(deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsStore.settings.deductExpensesFromProfit))
                                            ? settingsStore.settings.profitLossColorScheme.winColor
                                            : (session.isLossForDisplay(deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsStore.settings.deductExpensesFromProfit)) ? settingsStore.settings.profitLossColorScheme.lossColor : .secondary)
                                        )
                                    if session.id == preselectedSessionID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add to Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct OddsCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        OddsCalculatorView()
            .environmentObject(SubscriptionStore.shared)
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
