//
//  EditSessionView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    let session: PokerSession
    
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
    @State private var buyIn: String = ""
    @State private var cashOut: String = ""
    @State private var tournamentPosition: String = ""
    @State private var rebuys: String = ""
    @State private var handNotes: String = ""
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var imageIds: [String] = []
    @State private var selectedTags: Set<String> = []
    @State private var showSessionDetails = true
    @State private var showTournamentDetails = true
    @State private var showNotesAndTags = false
    @State private var showAttachments = false
    
    private let calendar = Calendar.current
    
    private var parsedAmount: Double? {
        let cleaned = amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
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
    
    var body: some View {
        NavigationStack {
            Form {
                quickEntrySection
                gameSection
                sessionDetailsSection
                if gameType == .tournament || gameType == .sitAndGo {
                    tournamentSection
                }
                notesAndTagsSection
                attachmentsSection
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Session")
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
            .onAppear { loadSession() }
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
        }
    }

    private var quickEntrySection: some View {
        Section("Quick Entry") {
            HStack {
                Text("Amount")
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
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
                    .keyboardType(.decimalPad)

                if supportsStakes {
                    HStack {
                        Text("Stakes")
                        Spacer()
                        StakesInputView(stakes: $stakes, currency: settingsStore.settings.currency)
                            .frame(maxWidth: 120)
                    }
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
                    .keyboardType(.decimalPad)
                TextField("Cash Out", text: $cashOut)
                    .keyboardType(.decimalPad)
                TextField("Tournament Position", text: $tournamentPosition)
                    .keyboardType(.numberPad)
                TextField("Rebuys", text: $rebuys)
                    .keyboardType(.numberPad)
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
                TextField("Hand notes", text: $handNotes, axis: .vertical)
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
                if !session.attachedHands.isEmpty {
                    AttachedHandsPreviewList(hands: session.attachedHands)
                }
                ImageAttachmentsSection(imageIds: $imageIds, deleteOnRemove: false, wrapInSection: false)
            }
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
    
    private func loadSession() {
        isWin = session.amount >= 0
        amount = String(format: "%.2f", abs(session.amount))
        date = session.date
        gameType = session.gameType == .plo ? .cash : session.gameType
        loadVariant(session.displayVariant)
        notes = session.notes
        hoursPlayed = session.hoursPlayed.map { String(format: "%.1f", $0) } ?? ""
        stakes = session.stakes ?? ""
        venue = session.venue ?? ""
        startTime = session.startTime
        endTime = session.endTime
        buyIn = session.buyIn.map { String(format: "%.2f", $0) } ?? ""
        cashOut = session.cashOut.map { String(format: "%.2f", $0) } ?? ""
        tournamentPosition = session.tournamentPosition.map { String($0) } ?? ""
        rebuys = session.rebuys.map { String($0) } ?? ""
        handNotes = session.handNotes ?? ""
        imageIds = session.imageIds
        selectedTags = Set(session.tags)
        showSessionDetails = true
        showTournamentDetails = session.gameType == .tournament || session.gameType == .sitAndGo
        showNotesAndTags = !trimmed(notes).isEmpty || !trimmed(handNotes).isEmpty || !selectedTags.isEmpty
        showAttachments = !imageIds.isEmpty || !session.attachedHands.isEmpty
        autoPopulateMissingTimeFields()
    }

    private func autoPopulateMissingTimeFields() {
        if let calculated = PokerSession.calculatedHours(from: startTime, to: endTime),
           hoursPlayed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hoursPlayed = String(format: "%.1f", calculated)
            return
        }

        guard let hours = Double(hoursPlayed), hours > 0 else { return }

        if startTime != nil, endTime == nil {
            endTime = PokerSession.endTime(from: startTime, hoursPlayed: hours)
        } else if endTime != nil, startTime == nil {
            startTime = PokerSession.startTime(from: endTime, hoursPlayed: hours)
        }
    }
    
    private func save() {
        guard let parsedAmount else { return }
        if settingsStore.settings.hapticFeedback {
            HapticManager.success()
        }
        let finalAmount = isWin ? parsedAmount : -parsedAmount
        let calculatedHours = PokerSession.calculatedHours(from: startTime, to: endTime)
        let finalHoursPlayed = calculatedHours ?? Double(hoursPlayed)
        let normalizedVariant = trimmed(finalVariant)
        let normalizedStakes = trimmed(stakes)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandNotes = handNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBuyIn = isTournamentGame ? Double(buyIn) : nil
        let finalCashOut = isTournamentGame ? Double(cashOut) : nil
        let finalTournamentPosition = isTournamentGame ? Int(tournamentPosition) : nil
        let finalRebuys = isTournamentGame ? Int(rebuys) : nil
        var updated = session
        updated.amount = finalAmount
        updated.date = date
        updated.gameType = gameType
        updated.variant = normalizedVariant.isEmpty ? nil : normalizedVariant
        updated.notes = normalizedNotes
        updated.hoursPlayed = finalHoursPlayed
        updated.stakes = (supportsStakes && !normalizedStakes.isEmpty) ? normalizedStakes : nil
        updated.venue = VenueCleaner.clean(venue)
        updated.startTime = startTime
        updated.endTime = endTime
        updated.buyIn = finalBuyIn
        updated.cashOut = finalCashOut
        updated.tournamentPosition = finalTournamentPosition
        updated.rebuys = finalRebuys
        updated.handNotes = normalizedHandNotes.isEmpty ? nil : normalizedHandNotes
        updated.imageIds = imageIds
        updated.tags = Array(selectedTags).sorted()
        // Delete image files that were removed during edit
        let removedIds = Set(session.imageIds).subtracting(imageIds)
        SessionImageStore.delete(imageIds: Array(removedIds))
        sessionStore.updateSession(updated)
        dismiss()
    }

    private var sessionDetailsSummary: String {
        var parts: [String] = []
        if let hours = Double(trimmed(hoursPlayed)), hours > 0 {
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

    private var tournamentSummary: String {
        var parts: [String] = []
        if !trimmed(buyIn).isEmpty {
            parts.append("Buy-in \(trimmed(buyIn))")
        }
        if !trimmed(tournamentPosition).isEmpty {
            parts.append("Pos \(trimmed(tournamentPosition))")
        }
        if let rebuyCount = Int(trimmed(rebuys)), rebuyCount > 0 {
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
        if !session.attachedHands.isEmpty {
            parts.append("\(session.attachedHands.count) hand\(session.attachedHands.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Photos and attached hands" : parts.joined(separator: " • ")
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
