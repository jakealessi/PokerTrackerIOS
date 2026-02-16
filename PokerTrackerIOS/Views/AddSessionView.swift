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
                    
                    TextField("Hours Played", text: $hoursPlayed)
                        .keyboardType(.decimalPad)
                    
                    HStack {
                        Text("Stakes")
                        TextField("e.g. $1/$2", text: $stakes)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack(spacing: 8) {
                        ForEach([StakesPreset.low1, .low2, .mid, .high], id: \.self) { preset in
                            Button(preset.rawValue) {
                                stakes = preset.rawValue
                                HapticManager.lightTap()
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(stakes == preset.rawValue ? AppTheme.accent.opacity(0.3) : AppTheme.cardBackground)
                            .foregroundStyle(stakes == preset.rawValue ? .white : .primary)
                            .cornerRadius(8)
                        }
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
                
                Section("Notes") {
                    TextField("Session notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Notable hands", text: $handNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    HStack {
                        Spacer()
                        ForEach([25, 50, 100, 200, 500], id: \.self) { n in
                            Button("\(n)") {
                                if amount.isEmpty || Double(amount) == 0 {
                                    amount = String(n)
                                } else if let current = Double(amount.replacingOccurrences(of: ",", with: "")) {
                                    amount = String(format: "%.0f", current + Double(n))
                                }
                                HapticManager.lightTap()
                            }
                            .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.horizontal)
                }
            }
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
            stakes: stakes.isEmpty ? nil : stakes,
            venue: venue.isEmpty ? nil : venue,
            buyIn: Double(buyIn),
            cashOut: Double(cashOut),
            tournamentPosition: Int(tournamentPosition),
            rebuys: Int(rebuys),
            handNotes: handNotes.isEmpty ? nil : handNotes
        )
        sessionStore.addSession(session)
        dismiss()
    }
}

#Preview {
    AddSessionView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
