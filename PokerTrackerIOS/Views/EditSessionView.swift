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
                    TextField("Hours Played", text: $hoursPlayed)
                        .keyboardType(.decimalPad)
                    TextField("Stakes (e.g. $1/$2)", text: $stakes)
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
                
                Section("Notes") {
                    TextField("Session notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Hand notes", text: $handNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
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
        }
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
        buyIn = session.buyIn.map { String(format: "%.2f", $0) } ?? ""
        cashOut = session.cashOut.map { String(format: "%.2f", $0) } ?? ""
        tournamentPosition = session.tournamentPosition.map { String($0) } ?? ""
        rebuys = session.rebuys.map { String($0) } ?? ""
        handNotes = session.handNotes ?? ""
    }
    
    private func save() {
        let finalAmount = isWin ? parsedAmount : -parsedAmount
        var updated = session
        updated.amount = finalAmount
        updated.date = date
        updated.gameType = gameType
        updated.variant = finalVariant.isEmpty ? nil : finalVariant
        updated.notes = notes
        updated.hoursPlayed = Double(hoursPlayed)
        updated.stakes = stakes.isEmpty ? nil : stakes
        updated.venue = venue.isEmpty ? nil : venue
        updated.buyIn = Double(buyIn)
        updated.cashOut = Double(cashOut)
        updated.tournamentPosition = Int(tournamentPosition)
        updated.rebuys = Int(rebuys)
        updated.handNotes = handNotes.isEmpty ? nil : handNotes
        sessionStore.updateSession(updated)
        dismiss()
    }
}
