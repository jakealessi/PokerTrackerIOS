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
    
    private let calendar = Calendar.current
    
    private var parsedAmount: Double {
        let cleaned = amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0
    }
    
    private var isValid: Bool { parsedAmount != 0 }
    
    private var finalVariant: String {
        isCustomVariant ? customVariant : selectedVariant
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
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
                
                Section("Session Details") {
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
                
                if gameType == .tournament || gameType == .sitAndGo {
                    Section("Tournament") {
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
                
                Section("Tags") {
                    TagPickerView(selectedTags: $selectedTags)
                }

                Section("Notes") {
                    TextField("Session notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Hand notes", text: $handNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                ImageAttachmentsSection(imageIds: $imageIds, deleteOnRemove: false)
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
        let finalAmount = isWin ? parsedAmount : -parsedAmount
        let calculatedHours = PokerSession.calculatedHours(from: startTime, to: endTime)
        let finalHoursPlayed = calculatedHours ?? Double(hoursPlayed)
        var updated = session
        updated.amount = finalAmount
        updated.date = date
        updated.gameType = gameType
        updated.variant = finalVariant.isEmpty ? nil : finalVariant
        updated.notes = notes
        updated.hoursPlayed = finalHoursPlayed
        updated.stakes = (gameType == .cash && !stakes.isEmpty) ? stakes : nil
        updated.venue = venue.isEmpty ? nil : venue
        updated.startTime = startTime
        updated.endTime = endTime
        updated.buyIn = Double(buyIn)
        updated.cashOut = Double(cashOut)
        updated.tournamentPosition = Int(tournamentPosition)
        updated.rebuys = Int(rebuys)
        updated.handNotes = handNotes.isEmpty ? nil : handNotes
        updated.imageIds = imageIds
        updated.tags = Array(selectedTags)
        // Delete image files that were removed during edit
        let removedIds = Set(session.imageIds).subtracting(imageIds)
        SessionImageStore.delete(imageIds: Array(removedIds))
        sessionStore.updateSession(updated)
        dismiss()
    }
}
