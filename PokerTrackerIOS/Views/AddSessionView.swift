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
    
    private let calendar = Calendar.current
    private let hasPrefilledGame: Bool

    init(prefilledAttachedHands: [PokerSession.AttachedHand] = [], prefilledVariant: String? = nil, prefilledStakes: String? = nil, prefilledGameType: GameType? = nil, prefilledVenue: String? = nil) {
        _attachedHands = State(initialValue: prefilledAttachedHands)
        let hasPrefill = prefilledVariant != nil || prefilledStakes != nil || prefilledGameType != nil
        self.hasPrefilledGame = hasPrefill
        if let v = prefilledVariant { _selectedVariant = State(initialValue: v) }
        if let s = prefilledStakes { _stakes = State(initialValue: s) }
        if let g = prefilledGameType { _gameType = State(initialValue: g) }
        if let ven = prefilledVenue, !ven.isEmpty { _venue = State(initialValue: ven) }
    }
    
    private var parsedAmount: Double {
        let cleaned = amount.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0
    }
    
    private var isValid: Bool { parsedAmount > 0 }
    
    private var finalVariant: String {
        isCustomVariant ? customVariant : selectedVariant
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session Result") {
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
                }
                
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
                
                Section("Details") {
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
                    
                    if gameType == .cash {
                        stakesSection
                    }
                    
                    TextField("Venue", text: $venue)
                }
                
                if gameType == .tournament || gameType == .sitAndGo {
                    Section("Tournament") {
                        TextField("Buy-in", text: $buyIn)
                            .keyboardType(.decimalPad)
                        TextField("Cash Out / Prize", text: $cashOut)
                            .keyboardType(.decimalPad)
                        TextField("Position", text: $tournamentPosition)
                            .keyboardType(.numberPad)
                        TextField("Rebuys", text: $rebuys)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section("Tags") {
                    TagPickerView(selectedTags: $selectedTags)
                }

                Section("Notes") {
                    TextField("Session notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Notable hands", text: $handNotes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !attachedHands.isEmpty {
                    Section("Attached Hands") {
                        ForEach(attachedHands) { hand in
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
                
                ImageAttachmentsSection(imageIds: $imageIds)
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
                guard !hasPrefilledGame else { return }
                if let last = sessionStore.lastSession {
                    gameType = last.gameType == .plo ? .cash : last.gameType
                    loadVariant(last.displayVariant)
                    stakes = last.stakes ?? settingsStore.settings.defaultStakes ?? ""
                    venue = last.venue ?? ""
                } else {
                    gameType = settingsStore.settings.defaultGameType
                    if let dv = settingsStore.settings.defaultVariant {
                        loadVariant(dv)
                    }
                    stakes = settingsStore.settings.defaultStakes ?? ""
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
    
    private func saveSession() {
        if settingsStore.settings.hapticFeedback {
            HapticManager.success()
        }
        let finalAmount = isWin ? parsedAmount : -parsedAmount
        let session = PokerSession(
            amount: finalAmount,
            date: date,
            notes: notes,
            gameType: gameType,
            variant: finalVariant.isEmpty ? nil : finalVariant,
            hoursPlayed: Double(hoursPlayed),
            stakes: (gameType == .cash && !stakes.isEmpty) ? stakes : nil,
            venue: venue.isEmpty ? nil : venue,
            buyIn: Double(buyIn),
            cashOut: Double(cashOut),
            tournamentPosition: Int(tournamentPosition),
            rebuys: Int(rebuys),
            handNotes: handNotes.isEmpty ? nil : handNotes,
            attachedHands: attachedHands,
            startTime: startTime,
            endTime: endTime,
            imageIds: imageIds,
            tags: Array(selectedTags)
        )
        sessionStore.addSession(session)
        dismiss()
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

#Preview {
    AddSessionView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
