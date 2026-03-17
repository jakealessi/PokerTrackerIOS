//
//  AddSessionView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct AddSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    
    @State private var amount: String = ""
    @State private var isWin: Bool = true
    @State private var date: Date = Date()
    @State private var gameType: GameType = .cash
    @State private var selectedVariant: String = PokerVariant.noLimitHoldem.rawValue
    @State private var customVariant: String = ""
    @State private var isCustomVariant: Bool = false
    @State private var notes: String = ""
    @State private var hoursPlayed: String = ""
    @State private var stakes: String = ""
    @State private var venue: String = ""
    @State private var rake: String = ""
    @State private var tips: String = ""
    @State private var food: String = ""
    @State private var travel: String = ""
    @State private var fees: String = ""
    @State private var buyIn: String = ""
    @State private var cashOut: String = ""
    @State private var tournamentPosition: String = ""
    @State private var rebuys: String = ""
    @State private var handNotes: String = ""
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var imageIds: [String] = []
    @State private var attachedHands: [PokerSession.AttachedHand]
    @State private var selectedTags: Set<String> = []
    @State private var showSessionDetails: Bool
    @State private var showTournamentDetails: Bool
    @State private var showExpenses: Bool
    @State private var showNotesAndTags: Bool
    @State private var showAttachments: Bool
    @State private var didSave = false
    
    private let calendar = Calendar.current
    private let hasPrefilledVariant: Bool
    private let hasPrefilledStakes: Bool
    private let hasPrefilledGameType: Bool
    private let hasPrefilledVenue: Bool

    init(prefilledAttachedHands: [PokerSession.AttachedHand] = [], prefilledVariant: String? = nil, prefilledStakes: String? = nil, prefilledGameType: GameType? = nil, prefilledVenue: String? = nil) {
        _attachedHands = State(initialValue: prefilledAttachedHands)
        _showSessionDetails = State(initialValue: prefilledStakes != nil || (prefilledVenue?.isEmpty == false))
        _showTournamentDetails = State(initialValue: prefilledGameType == .tournament || prefilledGameType == .sitAndGo)
        _showExpenses = State(initialValue: false)
        _showNotesAndTags = State(initialValue: false)
        _showAttachments = State(initialValue: !prefilledAttachedHands.isEmpty)
        self.hasPrefilledVariant = prefilledVariant != nil
        self.hasPrefilledStakes = prefilledStakes != nil
        self.hasPrefilledGameType = prefilledGameType != nil
        self.hasPrefilledVenue = prefilledVenue?.isEmpty == false
        if let v = prefilledVariant { _selectedVariant = State(initialValue: v) }
        if let s = prefilledStakes { _stakes = State(initialValue: s) }
        if let g = prefilledGameType { _gameType = State(initialValue: g) }
        if let ven = prefilledVenue, !ven.isEmpty { _venue = State(initialValue: ven) }
    }
    
    private var parsedAmount: Double? {
        parsedUnsignedCurrency(amount)
    }
    
    private var isValid: Bool { parsedAmount != nil }
    
    private var finalVariant: String {
        isCustomVariant ? customVariant : selectedVariant
    }

    private var supportsStakes: Bool {
        gameType == .cash || gameType == .homeGame || gameType == .online
    }

    private var isTournamentGame: Bool {
        gameType == .tournament || gameType == .sitAndGo
    }

    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }
    private var parsedExpenseTotal: Double {
        [rake, tips, food, travel, fees].compactMap { parsedExpense($0) }.reduce(0, +)
    }
    private var expenseItemCount: Int {
        [rake, tips, food, travel, fees].compactMap { parsedExpense($0) }.count
    }
    private var netAmountPreview: Double? {
        guard let gross = parsedAmount else { return nil }
        let signedGross = isWin ? gross : -gross
        return signedGross - parsedExpenseTotal
    }
    
    var body: some View {
        NavigationStack {
            Form {
                quickEntrySection
                gameSection
                sessionDetailsSection
                if gameType == .tournament || gameType == .sitAndGo {
                    tournamentSection
                }
                expensesSection
                notesAndTagsSection
                attachmentsSection
            }
            .navigationTitle("Log Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Log Session")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSession() }
                        .fontWeight(.semibold)
                        .foregroundStyle(isValid ? AppTheme.accent : AppTheme.secondaryText)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let last = sessionStore.lastSession {
                    if !hasPrefilledGameType {
                        gameType = last.gameType == .plo ? .cash : last.gameType
                    }
                    if !hasPrefilledVariant {
                        loadVariant(last.displayVariant)
                    }
                    if !hasPrefilledStakes {
                        stakes = last.stakes ?? settingsStore.settings.defaultStakes ?? ""
                    }
                    if !hasPrefilledVenue {
                        venue = last.venue ?? ""
                    }
                } else {
                    if !hasPrefilledGameType {
                        gameType = settingsStore.settings.defaultGameType
                    }
                    if !hasPrefilledVariant, let dv = settingsStore.settings.defaultVariant {
                        loadVariant(dv)
                    }
                    if !hasPrefilledStakes {
                        stakes = settingsStore.settings.defaultStakes ?? ""
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: startTime) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: endTime) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: hoursPlayed) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: gameType) { _, newValue in
                let nextSupportsStakes = newValue == .cash || newValue == .homeGame || newValue == .online
                if nextSupportsStakes {
                    showSessionDetails = true
                }
                if newValue == .tournament || newValue == .sitAndGo {
                    showTournamentDetails = true
                }
            }
            .onDisappear {
                guard !didSave, !imageIds.isEmpty else { return }
                SessionImageStore.delete(imageIds: imageIds)
            }
        }
    }

    private var quickEntrySection: some View {
        Section("Quick Entry") {
            HStack {
                Text("Table Result")
                TextField("0.00", text: $amount)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Result", selection: $isWin) {
                Text("Win").tag(true)
                Text("Loss").tag(false)
            }
            .pickerStyle(.segmented)

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .onChange(of: date) { _, newDate in
                    if let start = startTime {
                        let comps = calendar.dateComponents([.hour, .minute], from: start)
                        startTime = calendar.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: newDate)
                    }
                    if let end = endTime {
                        let comps = calendar.dateComponents([.hour, .minute], from: end)
                        endTime = calendar.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: newDate)
                    }
                }
        }
    }

    private var gameSection: some View {
        Section("Game") {
            Picker("Format", selection: $gameType) {
                ForEach(GameType.formatOptions, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            Picker("Variant", selection: $selectedVariant) {
                ForEach(PokerVariant.allCases, id: \.rawValue) { variant in
                    Text(variant.rawValue).tag(variant.rawValue)
                }
                Text("Custom").tag("__custom__")
            }
            .onChange(of: selectedVariant) { _, newValue in
                isCustomVariant = (newValue == "__custom__")
            }

            if isCustomVariant {
                TextField("Enter variant name", text: $customVariant)
            }
        }
    }

    private var sessionDetailsSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Session Details",
                summary: sessionDetailsSummary,
                systemImage: "clock.badge",
                isExpanded: $showSessionDetails
            )
            if showSessionDetails {
                Toggle("Add start time", isOn: Binding(
                    get: { startTime != nil },
                    set: { if $0 { startTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: date) ?? date } else { startTime = nil } }
                ))
                if startTime != nil {
                    DatePicker("Start", selection: timeBinding(for: date, time: $startTime), displayedComponents: .hourAndMinute)
                }

                Toggle("Add end time", isOn: Binding(
                    get: { endTime != nil },
                    set: { if $0 { endTime = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: date) ?? date } else { endTime = nil } }
                ))
                if endTime != nil {
                    DatePicker("End", selection: timeBinding(for: date, time: $endTime), displayedComponents: .hourAndMinute)
                }

                TextField("Hours Played", text: $hoursPlayed)
                    .keyboardType(.numbersAndPunctuation)

                if supportsStakes {
                    stakesSection
                }

                TextField("Venue", text: $venue)
            }
        }
    }

    private var tournamentSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Tournament Details",
                summary: tournamentSummary,
                systemImage: "trophy",
                isExpanded: $showTournamentDetails
            )
            if showTournamentDetails {
                TextField("Buy-in", text: $buyIn)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Cash Out / Prize", text: $cashOut)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Position", text: $tournamentPosition)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Rebuys", text: $rebuys)
                    .keyboardType(.numbersAndPunctuation)
            }
        }
    }

    private var expensesSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Expenses & Fees",
                summary: expensesSummary,
                systemImage: "creditcard",
                isExpanded: $showExpenses
            )
            if showExpenses {
                SessionCurrencyInputRow(label: "Rake", text: $rake)
                SessionCurrencyInputRow(label: "Tips", text: $tips)
                SessionCurrencyInputRow(label: "Food", text: $food)
                SessionCurrencyInputRow(label: "Travel", text: $travel)
                SessionCurrencyInputRow(label: "Fees", text: $fees)

                if parsedExpenseTotal > 0 {
                    LabeledContent("Total Expenses") {
                        Text(PokerSession.formatCurrency(parsedExpenseTotal, currency: settingsStore.settings.currency))
                            .foregroundStyle(.secondary)
                    }
                }

                if let netAmountPreview {
                    LabeledContent("Net Bankroll Change") {
                        Text(PokerSession.formatCurrency(netAmountPreview, currency: settingsStore.settings.currency))
                            .foregroundStyle(netAmountPreview >= 0 ? winColor : lossColor)
                    }
                }
            }
        }
    }

    private var notesAndTagsSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Notes & Tags",
                summary: notesAndTagsSummary,
                systemImage: "text.badge.plus",
                isExpanded: $showNotesAndTags
            )
            if showNotesAndTags {
                TagPickerView(selectedTags: $selectedTags)

                TextField("Session notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Notable hands", text: $handNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    private var attachmentsSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Attachments",
                summary: attachmentsSummary,
                systemImage: "paperclip",
                isExpanded: $showAttachments
            )
            if showAttachments {
                if !attachedHands.isEmpty {
                    AttachedHandsPreviewList(hands: attachedHands)
                }
                ImageAttachmentsSection(imageIds: $imageIds, wrapInSection: false)
            }
        }
    }
    
    private var stakesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stakes")
                Spacer()
                StakesInputView(stakes: $stakes, currency: settingsStore.settings.currency)
                    .frame(maxWidth: 120)
            }
            stakesPresetButtons
        }
    }
    
    private var stakesPresetButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StakesPreset.allCases, id: \.self) { preset in
                    Button {
                        stakes = preset.storedValue(currency: settingsStore.settings.currency)
                        HapticManager.lightTap()
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(stakes == preset.storedValue(currency: settingsStore.settings.currency) ? AppTheme.accent.opacity(0.3) : AppTheme.cardBackground)
                            .foregroundStyle(stakes == preset.storedValue(currency: settingsStore.settings.currency) ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func timeBinding(for sessionDate: Date, time: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: {
                time.wrappedValue ?? calendar.date(bySettingHour: 19, minute: 0, second: 0, of: sessionDate) ?? sessionDate
            },
            set: { newVal in
                let components = calendar.dateComponents([.hour, .minute], from: newVal)
                time.wrappedValue = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: sessionDate)
            }
        )
    }
    
    private func loadVariant(_ variant: String) {
        if PokerVariant.allCases.contains(where: { $0.rawValue == variant }) {
            selectedVariant = variant
            isCustomVariant = false
        } else {
            selectedVariant = "__custom__"
            customVariant = variant
            isCustomVariant = true
        }
    }

    private var sessionDetailsSummary: String {
        var parts: [String] = []
        if let hours = parsedHours(hoursPlayed), hours > 0 {
            parts.append("\(String(format: "%.1f", hours))h")
        } else if startTime != nil || endTime != nil {
            parts.append("Time added")
        }
        if supportsStakes, !trimmed(stakes).isEmpty {
            parts.append(stakes)
        }
        if !trimmed(venue).isEmpty {
            parts.append(trimmed(venue))
        }
        return parts.isEmpty ? "Venue, times, hours, and stakes" : parts.joined(separator: " • ")
    }

    private var expensesSummary: String {
        if parsedExpenseTotal > 0 {
            return "\(PokerSession.formatCurrency(parsedExpenseTotal, currency: settingsStore.settings.currency)) across \(expenseItemCount) item\(expenseItemCount == 1 ? "" : "s")"
        }
        return "Track rake, tips, food, travel, and fees"
    }

    private var tournamentSummary: String {
        var parts: [String] = []
        if !trimmed(buyIn).isEmpty {
            parts.append("Buy-in \(trimmed(buyIn))")
        }
        if !trimmed(tournamentPosition).isEmpty {
            parts.append("Pos \(trimmed(tournamentPosition))")
        }
        if let rebuyCount = parsedWholeNumber(rebuys), rebuyCount > 0 {
            parts.append("\(rebuyCount) rebuys")
        }
        return parts.isEmpty ? "Buy-in, cash out, placing, and rebuys" : parts.joined(separator: " • ")
    }

    private var notesAndTagsSummary: String {
        var parts: [String] = []
        if !selectedTags.isEmpty {
            parts.append("\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s")")
        }
        if !trimmed(notes).isEmpty || !trimmed(handNotes).isEmpty {
            parts.append("Notes added")
        }
        return parts.isEmpty ? "Optional notes, hand notes, and tags" : parts.joined(separator: " • ")
    }

    private var attachmentsSummary: String {
        var parts: [String] = []
        if !imageIds.isEmpty {
            parts.append("\(imageIds.count) photo\(imageIds.count == 1 ? "" : "s")")
        }
        if !attachedHands.isEmpty {
            parts.append("\(attachedHands.count) hand\(attachedHands.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Photos and attached hands" : parts.joined(separator: " • ")
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedUnsignedCurrency(_ value: String) -> Double? {
        guard let amount = SessionParserService.parseNumericValue(from: value) else { return nil }
        return abs(amount)
    }

    private func parsedExpense(_ value: String) -> Double? {
        guard let amount = parsedUnsignedCurrency(value), amount > 0.0001 else { return nil }
        return amount
    }

    private func parsedHours(_ value: String) -> Double? {
        let cleaned = trimmed(value)
        guard !cleaned.isEmpty else { return nil }
        if let parsed = SessionParserService.parseHoursValue(from: cleaned) {
            return parsed
        }
        if cleaned.rangeOfCharacter(from: CharacterSet.letters) != nil {
            return nil
        }
        return SessionParserService.parseNumericValue(from: cleaned)
    }

    private func parsedWholeNumber(_ value: String) -> Int? {
        let cleaned = trimmed(value)
        guard !cleaned.isEmpty else { return nil }
        return SessionParserService.parseOrdinalValue(from: cleaned)
    }

    private func autoPopulateMissingTimeFields() {
        if let calculated = PokerSession.calculatedHours(from: startTime, to: endTime),
           hoursPlayed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hoursPlayed = String(format: "%.1f", calculated)
            return
        }

        guard let hours = parsedHours(hoursPlayed), hours > 0 else { return }

        if startTime != nil, endTime == nil {
            endTime = PokerSession.endTime(from: startTime, hoursPlayed: hours)
        } else if endTime != nil, startTime == nil {
            startTime = PokerSession.startTime(from: endTime, hoursPlayed: hours)
        }
    }
    
    private func saveSession() {
        guard let parsedAmount else { return }
        if settingsStore.settings.hapticFeedback {
            HapticManager.success()
        }
        let finalAmount = isWin ? parsedAmount : -parsedAmount
        let calculatedHours = PokerSession.calculatedHours(from: startTime, to: endTime)
        let finalHoursPlayed = calculatedHours ?? parsedHours(hoursPlayed)
        let normalizedVariant = trimmed(finalVariant)
        let normalizedStakes = trimmed(stakes)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandNotes = handNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalRake = parsedExpense(rake)
        let finalTips = parsedExpense(tips)
        let finalFood = parsedExpense(food)
        let finalTravel = parsedExpense(travel)
        let finalFees = parsedExpense(fees)
        let finalBuyIn = isTournamentGame ? parsedUnsignedCurrency(buyIn) : nil
        let finalCashOut = isTournamentGame ? parsedUnsignedCurrency(cashOut) : nil
        let finalTournamentPosition = isTournamentGame ? parsedWholeNumber(tournamentPosition) : nil
        let finalRebuys = isTournamentGame ? parsedWholeNumber(rebuys) : nil
        let session = PokerSession(
            amount: finalAmount,
            date: date,
            notes: normalizedNotes,
            gameType: gameType,
            variant: normalizedVariant.isEmpty ? nil : normalizedVariant,
            hoursPlayed: finalHoursPlayed,
            stakes: (supportsStakes && !normalizedStakes.isEmpty) ? normalizedStakes : nil,
            venue: VenueCleaner.clean(venue),
            rake: finalRake,
            tips: finalTips,
            food: finalFood,
            travel: finalTravel,
            fees: finalFees,
            buyIn: finalBuyIn,
            cashOut: finalCashOut,
            tournamentPosition: finalTournamentPosition,
            rebuys: finalRebuys,
            handNotes: normalizedHandNotes.isEmpty ? nil : normalizedHandNotes,
            attachedHands: attachedHands,
            startTime: startTime,
            endTime: endTime,
            imageIds: imageIds,
            tags: Array(selectedTags).sorted()
        )
        sessionStore.addSession(session)
        didSave = true
        dismiss()
    }
}

struct SessionFormDisclosureHeader: View {
    let title: String
    let summary: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct SessionDisclosureToggleRow: View {
    let title: String
    let summary: String
    let systemImage: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(AppTheme.smoothSpring) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                SessionFormDisclosureHeader(
                    title: title,
                    summary: summary,
                    systemImage: systemImage
                )

                Spacer(minLength: 12)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SessionCurrencyInputRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AttachedHandsPreviewList: View {
    let hands: [PokerSession.AttachedHand]

    var body: some View {
        ForEach(hands) { hand in
            VStack(alignment: .leading, spacing: 4) {
                Text(hand.game)
                    .font(.subheadline.weight(.semibold))
                Text(hand.playerHands.joined(separator: " vs "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = hand.note, !note.isEmpty {
                    Text("Hand Note: \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Tag Picker

struct TagPickerView: View {
    @Binding var selectedTags: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SessionTag.allCases, id: \.rawValue) { tag in
                let isSelected = selectedTags.contains(tag.rawValue)
                Button {
                    if isSelected {
                        selectedTags.remove(tag.rawValue)
                    } else {
                        selectedTags.insert(tag.rawValue)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tag.icon)
                            .font(.caption2)
                        Text(tag.rawValue)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? tag.color.opacity(0.18) : Color(UIColor.tertiarySystemFill))
                    .foregroundStyle(isSelected ? tag.color : .primary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? tag.color.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Stakes Input

struct StakesInputView: View {
    @Binding var stakes: String
    var currency: String = "USD"
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case smallBlind, bigBlind
    }
    
    private var smallBlind: Binding<String> {
        Binding(
            get: { parseStakes(stakes).0 },
                set: { newVal in
                let (_, big) = parseStakes(stakes)
                stakes = formatStakes(small: newVal, big: big)
            }
        )
    }
    
    private var bigBlind: Binding<String> {
        Binding(
            get: { parseStakes(stakes).1 },
            set: { newVal in
                let (small, _) = parseStakes(stakes)
                stakes = formatStakes(small: small, big: newVal)
            }
        )
    }
    
    private var currencySymbol: String {
        StakesPreset.symbol(for: currency)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(currencySymbol)
                .font(.body)
                .foregroundStyle(.secondary)
            TextField("0", text: smallBlind)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .smallBlind)
            Text("/")
                .font(.body)
                .foregroundStyle(.secondary)
            TextField("0", text: bigBlind)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .bigBlind)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(8)
    }
    
    private func parseStakes(_ s: String) -> (String, String) {
        var cleaned = s
        for sym in ["$", "€", "£"] { cleaned = cleaned.replacingOccurrences(of: sym, with: "") }
        let parts = cleaned.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        }
        if parts.count == 1, !parts[0].isEmpty {
            return (parts[0], "")
        }
        return ("", "")
    }
    
    private func formatStakes(small: String, big: String) -> String {
        if small.isEmpty && big.isEmpty { return "" }
        if small.isEmpty { return "\(currencySymbol)/\(big)" }
        if big.isEmpty { return "\(currencySymbol)\(small)/" }
        return "\(currencySymbol)\(small)/\(currencySymbol)\(big)"
    }
}

private struct AddSessionView_Previews: PreviewProvider {
    static var previews: some View {
        AddSessionView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
