//
//  SessionEditorView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct AddSessionPrefill {
    var attachedHands: [PokerSession.AttachedHand] = []
    var variant: String?
    var stakes: String?
    var gameType: GameType?
    var venue: String?

    var hasPrefilledVariant: Bool { variant != nil }
    var hasPrefilledStakes: Bool { stakes != nil }
    var hasPrefilledGameType: Bool { gameType != nil }
    var hasPrefilledVenue: Bool { venue?.isEmpty == false }
}

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var draft: SessionEditorDraft
    @State private var didSave = false
    @State private var didApplyAddDefaults = false
    @State private var didPerformInitialAutofill = false
    @State private var transientEditImageIDs: Set<String> = []
    @State private var disabledAutoTimeFields: Set<SessionEditorTimeField> = []
    @State private var showingOddsCalculator = false

    private let mode: SessionEditorMode
    private let calendar = Calendar.current

    init(prefill: AddSessionPrefill = AddSessionPrefill()) {
        mode = .add(prefill)
        _draft = State(initialValue: .add(prefill: prefill))
    }

    init(session: PokerSession) {
        mode = .edit(session)
        _draft = State(initialValue: .edit(session))
    }

    private var parsedAmount: Double? {
        parsedUnsignedCurrency(draft.amount)
    }

    private var isValid: Bool { parsedAmount != nil }

    private var finalVariant: String {
        draft.isCustomVariant ? draft.customVariant : draft.selectedVariant
    }

    private var supportsStakes: Bool {
        draft.gameType == .cash || draft.gameType == .homeGame || draft.gameType == .online
    }

    private var isTournamentGame: Bool {
        draft.gameType == .tournament || draft.gameType == .sitAndGo
    }

    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }

    private var parsedExpenseTotal: Double {
        [draft.rake, draft.tips, draft.food, draft.travel, draft.fees]
            .compactMap(parsedExpense)
            .reduce(0, +)
    }

    private var expenseItemCount: Int {
        [draft.rake, draft.tips, draft.food, draft.travel, draft.fees]
            .compactMap(parsedExpense)
            .count
    }

    private var netAmountPreview: Double? {
        guard let gross = parsedAmount else { return nil }
        let signedGross = draft.isWin ? gross : -gross
        return signedGross - parsedExpenseTotal
    }

    var body: some View {
        NavigationStack {
            Form {
                quickEntrySection
                gameSection
                sessionDetailsSection
                if isTournamentGame {
                    tournamentSection
                }
                expensesSection
                notesAndTagsSection
                attachmentsSection
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mode.title)
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(isValid ? AppTheme.accent : AppTheme.secondaryText)
                        .disabled(!isValid)
                }
            }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .onAppear {
                applyAddDefaultsIfNeeded()
                performInitialAutofillIfNeeded()
            }
            .onChange(of: draft.startTime) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: draft.endTime) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: draft.hoursPlayed) { _, _ in
                autoPopulateMissingTimeFields()
            }
            .onChange(of: draft.gameType) { _, newValue in
                let nextSupportsStakes = newValue == .cash || newValue == .homeGame || newValue == .online
                if nextSupportsStakes {
                    draft.showSessionDetails = true
                }
                if newValue == .tournament || newValue == .sitAndGo {
                    draft.showTournamentDetails = true
                }
            }
            .onChange(of: draft.imageIds) { oldValue, newValue in
                trackTransientEditImages(from: oldValue, to: newValue)
            }
            .onDisappear {
                cleanupUnsavedImages()
            }
            .sheet(isPresented: $showingOddsCalculator) {
                OddsCalculatorView(onHandCreated: addAttachedHandToDraft)
            }
        }
    }

    private var quickEntrySection: some View {
        Section("Quick Entry") {
            HStack {
                Text("Table Result")
                TextField("0.00", text: $draft.amount)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Result", selection: $draft.isWin) {
                Text("Win").tag(true)
                Text("Loss").tag(false)
            }
            .pickerStyle(.segmented)

            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                .onChange(of: draft.date) { _, newDate in
                    if let start = draft.startTime {
                        let components = calendar.dateComponents([.hour, .minute], from: start)
                        draft.startTime = calendar.date(
                            bySettingHour: components.hour ?? 0,
                            minute: components.minute ?? 0,
                            second: 0,
                            of: newDate
                        )
                    }
                    if let end = draft.endTime {
                        let components = calendar.dateComponents([.hour, .minute], from: end)
                        draft.endTime = calendar.date(
                            bySettingHour: components.hour ?? 0,
                            minute: components.minute ?? 0,
                            second: 0,
                            of: newDate
                        )
                    }
                }
        }
    }

    private var gameSection: some View {
        Section("Game") {
            Picker("Format", selection: $draft.gameType) {
                ForEach(GameType.formatOptions, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            Picker("Variant", selection: $draft.selectedVariant) {
                ForEach(PokerVariant.allCases, id: \.rawValue) { variant in
                    Text(variant.rawValue).tag(variant.rawValue)
                }
                Text("Custom").tag("__custom__")
            }
            .onChange(of: draft.selectedVariant) { _, newValue in
                draft.isCustomVariant = (newValue == "__custom__")
            }

            if draft.isCustomVariant {
                TextField("Enter variant name", text: $draft.customVariant)
            }
        }
    }

    private var sessionDetailsSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Session Details",
                summary: sessionDetailsSummary,
                systemImage: "clock.badge",
                isExpanded: $draft.showSessionDetails
            )
            if draft.showSessionDetails {
                Toggle("Add start time", isOn: Binding(
                    get: { draft.startTime != nil },
                    set: {
                        if $0 {
                            disabledAutoTimeFields.remove(.start)
                            draft.startTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: draft.date) ?? draft.date
                        } else {
                            disabledAutoTimeFields.insert(.start)
                            draft.startTime = nil
                        }
                    }
                ))
                if draft.startTime != nil {
                    DatePicker(
                        "Start",
                        selection: timeBinding(for: .start, sessionDate: draft.date, time: $draft.startTime),
                        displayedComponents: .hourAndMinute
                    )
                }

                Toggle("Add end time", isOn: Binding(
                    get: { draft.endTime != nil },
                    set: {
                        if $0 {
                            disabledAutoTimeFields.remove(.end)
                            draft.endTime = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: draft.date) ?? draft.date
                        } else {
                            disabledAutoTimeFields.insert(.end)
                            draft.endTime = nil
                        }
                    }
                ))
                if draft.endTime != nil {
                    DatePicker(
                        "End",
                        selection: timeBinding(for: .end, sessionDate: draft.date, time: $draft.endTime),
                        displayedComponents: .hourAndMinute
                    )
                }

                TextField("Hours Played", text: $draft.hoursPlayed)
                    .keyboardType(.numbersAndPunctuation)

                if supportsStakes {
                    stakesSection
                }

                TextField("Venue", text: $draft.venue)

                if !venueQuickOptions.isEmpty {
                    venueQuickButtons
                }
            }
        }
    }

    private var tournamentSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Tournament Details",
                summary: tournamentSummary,
                systemImage: "trophy",
                isExpanded: $draft.showTournamentDetails
            )
            if draft.showTournamentDetails {
                TextField("Buy-in", text: $draft.buyIn)
                    .keyboardType(.numbersAndPunctuation)
                TextField(mode.cashOutLabel, text: $draft.cashOut)
                    .keyboardType(.numbersAndPunctuation)
                TextField(mode.tournamentPositionLabel, text: $draft.tournamentPosition)
                    .keyboardType(.numberPad)
                TextField("Rebuys", text: $draft.rebuys)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var expensesSection: some View {
        Section {
            SessionDisclosureToggleRow(
                title: "Expenses & Fees",
                summary: expensesSummary,
                systemImage: "creditcard",
                isExpanded: $draft.showExpenses
            )
            if draft.showExpenses {
                SessionCurrencyInputRow(label: "Rake", text: $draft.rake)
                SessionCurrencyInputRow(label: "Tips", text: $draft.tips)
                SessionCurrencyInputRow(label: "Food", text: $draft.food)
                SessionCurrencyInputRow(label: "Travel", text: $draft.travel)
                SessionCurrencyInputRow(label: "Fees", text: $draft.fees)

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
                isExpanded: $draft.showNotesAndTags
            )
            if draft.showNotesAndTags {
                TagPickerView(selectedTags: $draft.selectedTags)

                TextField("Session notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                TextField(mode.handNotesLabel, text: $draft.handNotes, axis: .vertical)
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
                isExpanded: $draft.showAttachments
            )
            if draft.showAttachments {
                if !draft.attachedHands.isEmpty {
                    AttachedHandsPreviewList(
                        hands: draft.attachedHands,
                        onRemove: removeAttachedHandFromDraft
                    )
                }
                ImageAttachmentsSection(
                    imageIds: $draft.imageIds,
                    deleteOnRemove: mode.deleteImagesOnRemove,
                    wrapInSection: false
                )
                Button {
                    showingOddsCalculator = true
                } label: {
                    Label("Add Hand", systemImage: "percent")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
        }
    }

    private var stakesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stakes")
                Spacer()
                StakesInputView(stakes: $draft.stakes, currency: settingsStore.settings.currency)
                    .frame(maxWidth: 120)
            }
            if !enabledStakesPresets.isEmpty {
                stakesPresetButtons
            }
        }
    }

    private var enabledStakesPresets: [StakesPreset] {
        StakesPreset.enabledPresets(from: settingsStore.settings.enabledStakesPresets)
    }

    private var venueQuickOptions: [VenueQuickOption] {
        sessionStore.venueQuickOptions(using: settingsStore.settings)
    }

    private var stakesPresetButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(enabledStakesPresets, id: \.self) { preset in
                    Button {
                        draft.stakes = preset.storedValue(currency: settingsStore.settings.currency)
                        HapticManager.lightTap()
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                draft.stakes == preset.storedValue(currency: settingsStore.settings.currency)
                                    ? AppTheme.accent.opacity(0.3)
                                    : AppTheme.cardBackground
                            )
                            .foregroundStyle(
                                draft.stakes == preset.storedValue(currency: settingsStore.settings.currency)
                                    ? .white
                                    : .primary
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var venueQuickButtons: some View {
        FlowLayout(spacing: 8) {
            ForEach(venueQuickOptions) { option in
                Button {
                    draft.venue = option.venue
                    HapticManager.lightTap()
                } label: {
                    Text(option.venue)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelectedVenueQuickOption(option)
                                ? AppTheme.accent.opacity(0.3)
                                : AppTheme.cardBackground
                        )
                        .foregroundStyle(
                            isSelectedVenueQuickOption(option)
                                ? .white
                                : .primary
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var sessionDetailsSummary: String {
        var parts: [String] = []
        if let hours = parsedHours(draft.hoursPlayed), hours > 0 {
            parts.append("\(String(format: "%.1f", hours))h")
        } else if draft.startTime != nil || draft.endTime != nil {
            parts.append("Time added")
        }
        if supportsStakes, !trimmed(draft.stakes).isEmpty {
            parts.append(draft.stakes)
        }
        if !trimmed(draft.venue).isEmpty {
            parts.append(trimmed(draft.venue))
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
        if !trimmed(draft.buyIn).isEmpty {
            parts.append("Buy-in \(trimmed(draft.buyIn))")
        }
        if !trimmed(draft.tournamentPosition).isEmpty {
            parts.append("Pos \(trimmed(draft.tournamentPosition))")
        }
        if let rebuyCount = parsedWholeNumber(draft.rebuys), rebuyCount > 0 {
            parts.append("\(rebuyCount) rebuys")
        }
        return parts.isEmpty ? "Buy-in, cash out, placing, and rebuys" : parts.joined(separator: " • ")
    }

    private var notesAndTagsSummary: String {
        var parts: [String] = []
        if !draft.selectedTags.isEmpty {
            parts.append("\(draft.selectedTags.count) tag\(draft.selectedTags.count == 1 ? "" : "s")")
        }
        if !trimmed(draft.notes).isEmpty || !trimmed(draft.handNotes).isEmpty {
            parts.append("Notes added")
        }
        return parts.isEmpty ? "Optional notes, hand notes, and tags" : parts.joined(separator: " • ")
    }

    private var attachmentsSummary: String {
        var parts: [String] = []
        if !draft.imageIds.isEmpty {
            parts.append("\(draft.imageIds.count) photo\(draft.imageIds.count == 1 ? "" : "s")")
        }
        if !draft.attachedHands.isEmpty {
            parts.append("\(draft.attachedHands.count) hand\(draft.attachedHands.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Photos and attached hands" : parts.joined(separator: " • ")
    }

    private func applyAddDefaultsIfNeeded() {
        guard case .add(let prefill) = mode, !didApplyAddDefaults else { return }
        didApplyAddDefaults = true

        if let last = sessionStore.lastSession {
            if !prefill.hasPrefilledGameType {
                draft.gameType = last.gameType == .plo ? .cash : last.gameType
            }
            if !prefill.hasPrefilledVariant {
                loadVariant(last.displayVariant)
            }
            if !prefill.hasPrefilledStakes {
                draft.stakes = last.stakes ?? settingsStore.settings.defaultStakes ?? ""
            }
            if !prefill.hasPrefilledVenue {
                draft.venue = last.venue ?? ""
            }
            if draft.gameType == .tournament || draft.gameType == .sitAndGo {
                draft.showTournamentDetails = true
            }
            return
        }

        if !prefill.hasPrefilledGameType {
            draft.gameType = settingsStore.settings.defaultGameType
        }
        if !prefill.hasPrefilledVariant, let defaultVariant = settingsStore.settings.defaultVariant {
            loadVariant(defaultVariant)
        }
        if !prefill.hasPrefilledStakes {
            draft.stakes = settingsStore.settings.defaultStakes ?? ""
        }
        if draft.gameType == .tournament || draft.gameType == .sitAndGo {
            draft.showTournamentDetails = true
        }
    }

    private func performInitialAutofillIfNeeded() {
        guard !didPerformInitialAutofill else { return }
        didPerformInitialAutofill = true
        autoPopulateMissingTimeFields()
    }

    private func cleanupUnsavedImages() {
        guard !didSave else { return }

        switch mode {
        case .add:
            guard !draft.imageIds.isEmpty else { return }
            SessionImageStore.delete(imageIds: draft.imageIds)
        case .edit(let session):
            let unsavedNewIDs = Set(draft.imageIds).subtracting(session.imageIds)
            let pendingCleanupIDs = unsavedNewIDs.union(transientEditImageIDs)
            guard !pendingCleanupIDs.isEmpty else { return }
            SessionImageStore.delete(imageIds: Array(pendingCleanupIDs))
        }
    }

    private func trackTransientEditImages(from oldValue: [String], to newValue: [String]) {
        guard case .edit(let session) = mode else { return }

        let previous = Set(oldValue)
        let current = Set(newValue)
        let original = Set(session.imageIds)

        let addedTransientIDs = current.subtracting(previous).subtracting(original)
        transientEditImageIDs.formUnion(addedTransientIDs)

        let removedTransientIDs = previous.subtracting(current).intersection(transientEditImageIDs)
        guard !removedTransientIDs.isEmpty else { return }

        transientEditImageIDs.subtract(removedTransientIDs)
        SessionImageStore.delete(imageIds: Array(removedTransientIDs))
    }

    private func timeBinding(for field: SessionEditorTimeField, sessionDate: Date, time: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: {
                time.wrappedValue ?? calendar.date(bySettingHour: 19, minute: 0, second: 0, of: sessionDate) ?? sessionDate
            },
            set: { newValue in
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                disabledAutoTimeFields.remove(field)
                time.wrappedValue = calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: sessionDate
                )
            }
        )
    }

    private func loadVariant(_ variant: String) {
        draft.setVariant(variant)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSelectedVenueQuickOption(_ option: VenueQuickOption) -> Bool {
        VenueCleaner.key(for: draft.venue) == VenueCleaner.key(for: option.venue)
    }

    private func addAttachedHandToDraft(_ hand: PokerSession.AttachedHand) {
        draft.attachedHands.append(hand)
        draft.showAttachments = true
        HapticManager.lightTap()
    }

    private func removeAttachedHandFromDraft(_ handID: UUID) {
        draft.attachedHands.removeAll { $0.id == handID }
        draft.showAttachments = !draft.imageIds.isEmpty || !draft.attachedHands.isEmpty
        HapticManager.lightTap()
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
        return SessionParserService.parseWholeNumberValue(from: cleaned)
    }

    private func autoPopulateMissingTimeFields() {
        if let calculated = PokerSession.calculatedHours(from: draft.startTime, to: draft.endTime),
           draft.hoursPlayed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.hoursPlayed = String(format: "%.1f", calculated)
            return
        }

        guard let hours = parsedHours(draft.hoursPlayed), hours > 0 else { return }

        if draft.startTime != nil,
           draft.endTime == nil,
           !disabledAutoTimeFields.contains(.end) {
            draft.endTime = PokerSession.endTime(from: draft.startTime, hoursPlayed: hours)
        } else if draft.endTime != nil,
                  draft.startTime == nil,
                  !disabledAutoTimeFields.contains(.start) {
            draft.startTime = PokerSession.startTime(from: draft.endTime, hoursPlayed: hours)
        }
    }

    private func save() {
        guard let parsedAmount else { return }

        if settingsStore.settings.hapticFeedback {
            HapticManager.success()
        }

        let finalAmount = draft.isWin ? parsedAmount : -parsedAmount
        let calculatedHours = PokerSession.calculatedHours(from: draft.startTime, to: draft.endTime)
        let finalHoursPlayed = calculatedHours ?? parsedHours(draft.hoursPlayed)
        let normalizedVariant = trimmed(finalVariant)
        let normalizedStakes = trimmed(draft.stakes)
        let normalizedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandNotes = draft.handNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalRake = parsedExpense(draft.rake)
        let finalTips = parsedExpense(draft.tips)
        let finalFood = parsedExpense(draft.food)
        let finalTravel = parsedExpense(draft.travel)
        let finalFees = parsedExpense(draft.fees)
        let finalBuyIn = isTournamentGame ? parsedUnsignedCurrency(draft.buyIn) : nil
        let finalCashOut = isTournamentGame ? parsedUnsignedCurrency(draft.cashOut) : nil
        let finalTournamentPosition = isTournamentGame ? parsedWholeNumber(draft.tournamentPosition) : nil
        let finalRebuys = isTournamentGame ? parsedWholeNumber(draft.rebuys) : nil

        switch mode {
        case .add:
            let session = PokerSession(
                amount: finalAmount,
                date: draft.date,
                notes: normalizedNotes,
                gameType: draft.gameType,
                variant: normalizedVariant.isEmpty ? nil : normalizedVariant,
                hoursPlayed: finalHoursPlayed,
                stakes: (supportsStakes && !normalizedStakes.isEmpty) ? normalizedStakes : nil,
                venue: VenueCleaner.clean(draft.venue),
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
                attachedHands: draft.attachedHands,
                startTime: draft.startTime,
                endTime: draft.endTime,
                imageIds: draft.imageIds,
                tags: Array(draft.selectedTags).sorted()
            )
            sessionStore.addSession(session)
        case .edit(let session):
            var updated = session
            updated.amount = finalAmount
            updated.date = draft.date
            updated.gameType = draft.gameType
            updated.variant = normalizedVariant.isEmpty ? nil : normalizedVariant
            updated.notes = normalizedNotes
            updated.hoursPlayed = finalHoursPlayed
            updated.stakes = (supportsStakes && !normalizedStakes.isEmpty) ? normalizedStakes : nil
            updated.venue = VenueCleaner.clean(draft.venue)
            updated.rake = finalRake
            updated.tips = finalTips
            updated.food = finalFood
            updated.travel = finalTravel
            updated.fees = finalFees
            updated.startTime = draft.startTime
            updated.endTime = draft.endTime
            updated.buyIn = finalBuyIn
            updated.cashOut = finalCashOut
            updated.tournamentPosition = finalTournamentPosition
            updated.rebuys = finalRebuys
            updated.handNotes = normalizedHandNotes.isEmpty ? nil : normalizedHandNotes
            updated.attachedHands = draft.attachedHands
            updated.imageIds = draft.imageIds
            updated.tags = Array(draft.selectedTags).sorted()
            sessionStore.updateSession(updated)
        }

        didSave = true
        dismiss()
    }
}

private enum SessionEditorMode {
    case add(AddSessionPrefill)
    case edit(PokerSession)

    var title: String {
        switch self {
        case .add:
            return "Log Session"
        case .edit:
            return "Edit Session"
        }
    }

    var cashOutLabel: String {
        switch self {
        case .add:
            return "Cash Out / Prize"
        case .edit:
            return "Cash Out"
        }
    }

    var tournamentPositionLabel: String {
        switch self {
        case .add:
            return "Position"
        case .edit:
            return "Tournament Position"
        }
    }

    var handNotesLabel: String {
        switch self {
        case .add:
            return "Notable hands"
        case .edit:
            return "Hand notes"
        }
    }

    var deleteImagesOnRemove: Bool {
        switch self {
        case .add:
            return true
        case .edit:
            return false
        }
    }
}

private enum SessionEditorTimeField: Hashable {
    case start
    case end
}

private struct SessionEditorDraft {
    var amount: String = ""
    var isWin: Bool = true
    var date: Date = Date()
    var gameType: GameType = .cash
    var selectedVariant: String = PokerVariant.noLimitHoldem.rawValue
    var customVariant: String = ""
    var isCustomVariant: Bool = false
    var notes: String = ""
    var hoursPlayed: String = ""
    var stakes: String = ""
    var venue: String = ""
    var rake: String = ""
    var tips: String = ""
    var food: String = ""
    var travel: String = ""
    var fees: String = ""
    var buyIn: String = ""
    var cashOut: String = ""
    var tournamentPosition: String = ""
    var rebuys: String = ""
    var handNotes: String = ""
    var startTime: Date?
    var endTime: Date?
    var imageIds: [String] = []
    var attachedHands: [PokerSession.AttachedHand] = []
    var selectedTags: Set<String> = []
    var showSessionDetails: Bool = false
    var showTournamentDetails: Bool = false
    var showExpenses: Bool = false
    var showNotesAndTags: Bool = false
    var showAttachments: Bool = false

    static func add(prefill: AddSessionPrefill) -> Self {
        var draft = Self()
        draft.attachedHands = prefill.attachedHands
        draft.showSessionDetails = prefill.hasPrefilledStakes || prefill.hasPrefilledVenue
        draft.showTournamentDetails = prefill.gameType == .tournament || prefill.gameType == .sitAndGo
        draft.showAttachments = !prefill.attachedHands.isEmpty

        if let variant = prefill.variant {
            draft.setVariant(variant)
        }
        if let stakes = prefill.stakes {
            draft.stakes = stakes
        }
        if let gameType = prefill.gameType {
            draft.gameType = gameType
        }
        if let venue = prefill.venue, !venue.isEmpty {
            draft.venue = venue
        }

        return draft
    }

    static func edit(_ session: PokerSession) -> Self {
        var draft = Self()
        draft.isWin = session.amount >= 0
        draft.amount = String(format: "%.2f", abs(session.amount))
        draft.date = session.date
        draft.gameType = session.gameType == .plo ? .cash : session.gameType
        draft.setVariant(session.displayVariant)
        draft.notes = session.notes
        draft.hoursPlayed = session.hoursPlayed.map { String(format: "%.1f", $0) } ?? ""
        draft.stakes = session.stakes ?? ""
        draft.venue = session.venue ?? ""
        draft.rake = session.rake.map { String(format: "%.2f", $0) } ?? ""
        draft.tips = session.tips.map { String(format: "%.2f", $0) } ?? ""
        draft.food = session.food.map { String(format: "%.2f", $0) } ?? ""
        draft.travel = session.travel.map { String(format: "%.2f", $0) } ?? ""
        draft.fees = session.fees.map { String(format: "%.2f", $0) } ?? ""
        draft.buyIn = session.buyIn.map { String(format: "%.2f", $0) } ?? ""
        draft.cashOut = session.cashOut.map { String(format: "%.2f", $0) } ?? ""
        draft.tournamentPosition = session.tournamentPosition.map(String.init) ?? ""
        draft.rebuys = session.rebuys.map(String.init) ?? ""
        draft.handNotes = session.handNotes ?? ""
        draft.startTime = session.startTime
        draft.endTime = session.endTime
        draft.imageIds = session.imageIds
        draft.attachedHands = session.attachedHands
        draft.selectedTags = Set(session.tags)
        draft.showSessionDetails = true
        draft.showTournamentDetails = session.gameType == .tournament || session.gameType == .sitAndGo
        draft.showExpenses = session.hasExpenses
        draft.showNotesAndTags =
            !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !draft.handNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !draft.selectedTags.isEmpty
        draft.showAttachments = !draft.imageIds.isEmpty || !draft.attachedHands.isEmpty
        return draft
    }

    mutating func setVariant(_ variant: String) {
        if PokerVariant.allCases.contains(where: { $0.rawValue == variant }) {
            selectedVariant = variant
            isCustomVariant = false
        } else {
            selectedVariant = "__custom__"
            customVariant = variant
            isCustomVariant = true
        }
    }
}

private struct SessionFormDisclosureHeader: View {
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

private struct SessionDisclosureToggleRow: View {
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

private struct SessionCurrencyInputRow: View {
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

private struct AttachedHandsPreviewList: View {
    let hands: [PokerSession.AttachedHand]
    let onRemove: (UUID) -> Void

    var body: some View {
        ForEach(hands) { hand in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    Text(hand.game)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) {
                        onRemove(hand.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
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

private struct TagPickerView: View {
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

private struct StakesInputView: View {
    @Binding var stakes: String
    var currency: String = "USD"
    @FocusState private var focusedField: Field?

    private enum Field {
        case smallBlind
        case bigBlind
    }

    private var smallBlind: Binding<String> {
        Binding(
            get: { parseStakes(stakes).0 },
            set: { newValue in
                let (_, big) = parseStakes(stakes)
                stakes = formatStakes(small: newValue, big: big)
            }
        )
    }

    private var bigBlind: Binding<String> {
        Binding(
            get: { parseStakes(stakes).1 },
            set: { newValue in
                let (small, _) = parseStakes(stakes)
                stakes = formatStakes(small: small, big: newValue)
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

    private func parseStakes(_ stakes: String) -> (String, String) {
        var cleaned = stakes
        let symbols = Set(SupportedCurrency.all.map(\.symbol))
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs > rhs
            }

        for symbol in symbols {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "", options: [.caseInsensitive])
        }

        let parts = cleaned.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return (
                parts[0].trimmingCharacters(in: .whitespaces),
                parts[1].trimmingCharacters(in: .whitespaces)
            )
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
