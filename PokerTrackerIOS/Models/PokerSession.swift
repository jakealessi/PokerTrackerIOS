//
//  PokerSession.swift
//  PokerTrackerIOS
//

import Foundation

struct PokerSession: Identifiable, Codable, Equatable {
    let id: UUID
    var sessionNumber: Int
    var amount: Double
    var date: Date
    var notes: String
    var gameType: GameType
    var variant: String?
    var hoursPlayed: Double?
    var stakes: String?
    var venue: String?
    var buyIn: Double?
    var cashOut: Double?
    var tournamentPosition: Int?
    var rebuys: Int?
    var handNotes: String?
    
    init(
        id: UUID = UUID(),
        sessionNumber: Int = 0,
        amount: Double,
        date: Date = Date(),
        notes: String = "",
        gameType: GameType = .cash,
        variant: String? = nil,
        hoursPlayed: Double? = nil,
        stakes: String? = nil,
        venue: String? = nil,
        buyIn: Double? = nil,
        cashOut: Double? = nil,
        tournamentPosition: Int? = nil,
        rebuys: Int? = nil,
        handNotes: String? = nil
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
        self.amount = amount
        self.date = date
        self.notes = notes
        self.gameType = gameType
        self.variant = variant
        self.hoursPlayed = hoursPlayed
        self.stakes = stakes
        self.venue = venue
        self.buyIn = buyIn
        self.cashOut = cashOut
        self.tournamentPosition = tournamentPosition
        self.rebuys = rebuys
        self.handNotes = handNotes
    }
    
    // Migration: if sessionNumber is missing from old data, default to 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sessionNumber = try c.decodeIfPresent(Int.self, forKey: .sessionNumber) ?? 0
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        gameType = try c.decodeIfPresent(GameType.self, forKey: .gameType) ?? .cash
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        hoursPlayed = try c.decodeIfPresent(Double.self, forKey: .hoursPlayed)
        stakes = try c.decodeIfPresent(String.self, forKey: .stakes)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        buyIn = try c.decodeIfPresent(Double.self, forKey: .buyIn)
        cashOut = try c.decodeIfPresent(Double.self, forKey: .cashOut)
        tournamentPosition = try c.decodeIfPresent(Int.self, forKey: .tournamentPosition)
        rebuys = try c.decodeIfPresent(Int.self, forKey: .rebuys)
        handNotes = try c.decodeIfPresent(String.self, forKey: .handNotes)
    }
    
    var isWin: Bool { amount > 0 }
    
    var hourlyRate: Double? {
        guard let hours = hoursPlayed, hours > 0 else { return nil }
        return amount / hours
    }
    
    var tournamentROI: Double? {
        guard gameType == .tournament || gameType == .sitAndGo,
              let buyIn = buyIn, buyIn > 0 else { return nil }
        let totalBuyIn = buyIn + Double(rebuys ?? 0) * buyIn
        return totalBuyIn > 0 ? (amount / totalBuyIn) * 100 : nil
    }
    
    var formattedAmount: String {
        Self.formatCurrency(amount)
    }
    
    /// Display string: variant if set, otherwise game format
    var displayVariant: String {
        if let v = variant, !v.isEmpty { return v }
        // Migrate old PLO sessions
        if gameType == .plo { return PokerVariant.plo.rawValue }
        return PokerVariant.noLimitHoldem.rawValue
    }
    
    static func formatCurrency(_ value: Double, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}

// MARK: - Game Format (Cash, Tournament, etc.)
enum GameType: String, Codable, CaseIterable {
    case cash = "Cash Game"
    case plo = "PLO"
    case tournament = "Tournament"
    case sitAndGo = "Sit & Go"
    case homeGame = "Home Game"
    case online = "Online"
    
    /// Formats shown in pickers (excludes legacy PLO entry)
    static var formatOptions: [GameType] {
        [.cash, .tournament, .sitAndGo, .homeGame, .online]
    }
}

// MARK: - Poker Variant presets
enum PokerVariant: String, CaseIterable {
    case noLimitHoldem = "No Limit Hold'em"
    case limitHoldem = "Limit Hold'em"
    case plo = "Pot Limit Omaha"
    case ploHiLo = "PLO Hi-Lo"
    case omahaHiLo = "Omaha Hi-Lo"
    case fiveCardPlo = "5-Card PLO"
    case sevenCardStud = "Seven Card Stud"
    case studHiLo = "Stud Hi-Lo"
    case razz = "Razz"
    case tripleDraw = "2-7 Triple Draw"
    case badugi = "Badugi"
    case shortDeck = "Short Deck (6+)"
    case openFaceChinese = "Open Face Chinese"
    case mixed = "Mixed Games"
}

// MARK: - Stakes presets
enum StakesPreset: String, CaseIterable {
    case micro = "$0.25/$0.50"
    case low1 = "$1/$2"
    case low2 = "$2/$5"
    case mid = "$5/$10"
    case high = "$10/$25"
    case highRoller = "$25/$50+"
    case custom = "Custom"
}
