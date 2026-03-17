//
//  PokerSession.swift
//  PokerTrackerIOS
//

import Foundation
import SwiftUI

struct PokerSession: Identifiable, Codable, Equatable {
    struct AttachedHand: Identifiable, Codable, Equatable {
        let id: UUID
        var createdAt: Date
        var game: String
        var playerHands: [String]
        var board: String?
        var deadCards: String?
        var resultSummary: [String]
        var note: String?

        init(
            id: UUID = UUID(),
            createdAt: Date = Date(),
            game: String,
            playerHands: [String],
            board: String? = nil,
            deadCards: String? = nil,
            resultSummary: [String] = [],
            note: String? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.game = game
            self.playerHands = playerHands
            self.board = board
            self.deadCards = deadCards
            self.resultSummary = resultSummary
            self.note = note
        }
    }

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
    var rake: Double?
    var tips: Double?
    var food: Double?
    var travel: Double?
    var fees: Double?
    var buyIn: Double?
    var cashOut: Double?
    var tournamentPosition: Int?
    var rebuys: Int?
    var handNotes: String?
    var attachedHands: [AttachedHand]
    var startTime: Date?
    var endTime: Date?
    var imageIds: [String]
    var tags: [String]
    
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
        rake: Double? = nil,
        tips: Double? = nil,
        food: Double? = nil,
        travel: Double? = nil,
        fees: Double? = nil,
        buyIn: Double? = nil,
        cashOut: Double? = nil,
        tournamentPosition: Int? = nil,
        rebuys: Int? = nil,
        handNotes: String? = nil,
        attachedHands: [AttachedHand] = [],
        startTime: Date? = nil,
        endTime: Date? = nil,
        imageIds: [String] = [],
        tags: [String] = []
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
        self.rake = rake
        self.tips = tips
        self.food = food
        self.travel = travel
        self.fees = fees
        self.buyIn = buyIn
        self.cashOut = cashOut
        self.tournamentPosition = tournamentPosition
        self.rebuys = rebuys
        self.handNotes = handNotes
        self.attachedHands = attachedHands
        self.startTime = startTime
        self.endTime = endTime
        self.imageIds = imageIds
        self.tags = tags
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
        rake = try c.decodeIfPresent(Double.self, forKey: .rake)
        tips = try c.decodeIfPresent(Double.self, forKey: .tips)
        food = try c.decodeIfPresent(Double.self, forKey: .food)
        travel = try c.decodeIfPresent(Double.self, forKey: .travel)
        fees = try c.decodeIfPresent(Double.self, forKey: .fees)
        buyIn = try c.decodeIfPresent(Double.self, forKey: .buyIn)
        cashOut = try c.decodeIfPresent(Double.self, forKey: .cashOut)
        tournamentPosition = try c.decodeIfPresent(Int.self, forKey: .tournamentPosition)
        rebuys = try c.decodeIfPresent(Int.self, forKey: .rebuys)
        handNotes = try c.decodeIfPresent(String.self, forKey: .handNotes)
        attachedHands = try c.decodeIfPresent([AttachedHand].self, forKey: .attachedHands) ?? []
        startTime = try c.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        imageIds = try c.decodeIfPresent([String].self, forKey: .imageIds) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
    
    var totalExpenses: Double {
        expenseEntries.reduce(0) { $0 + $1.amount }
    }

    var hasExpenses: Bool { totalExpenses > 0.0001 }

    var netAmount: Double {
        amount - totalExpenses
    }

    var expenseEntries: [(label: String, amount: Double)] {
        [
            ("Rake", rake),
            ("Tips", tips),
            ("Food", food),
            ("Travel", travel),
            ("Fees", fees)
        ]
        .compactMap { label, amount in
            guard let amount, amount > 0 else { return nil }
            return (label: label, amount: amount)
        }
    }

    var isWin: Bool { netAmount > 0.0001 }
    var isLoss: Bool { netAmount < -0.0001 }
    var isBreakEven: Bool { abs(netAmount) <= 0.0001 }
    
    var hourlyRate: Double? {
        guard let hours = hoursPlayed, hours > 0 else { return nil }
        return netAmount / hours
    }
    
    var tournamentROI: Double? {
        guard gameType == .tournament || gameType == .sitAndGo,
              let buyIn = buyIn, buyIn > 0 else { return nil }
        let totalBuyIn = buyIn + Double(rebuys ?? 0) * buyIn
        return totalBuyIn > 0 ? (netAmount / totalBuyIn) * 100 : nil
    }
    
    var formattedAmount: String {
        Self.formatCurrency(netAmount)
    }

    static func calculatedHours(from startTime: Date?, to endTime: Date?) -> Double? {
        guard let startTime, let endTime else { return nil }
        var duration = endTime.timeIntervalSince(startTime)
        if duration <= 0 {
            duration += 24 * 60 * 60
        }
        guard duration > 0 else { return nil }
        return duration / 3600
    }

    static func endTime(from startTime: Date?, hoursPlayed: Double?) -> Date? {
        guard let startTime, let hoursPlayed, hoursPlayed.isFinite, hoursPlayed > 0 else { return nil }
        return startTime.addingTimeInterval(hoursPlayed * 3600)
    }

    static func startTime(from endTime: Date?, hoursPlayed: Double?) -> Date? {
        guard let endTime, let hoursPlayed, hoursPlayed.isFinite, hoursPlayed > 0 else { return nil }
        return endTime.addingTimeInterval(-hoursPlayed * 3600)
    }

    var normalizedGameType: GameType {
        gameType == .plo ? .cash : gameType
    }

    var displayGameType: String {
        normalizedGameType.rawValue
    }

    var displayGameTypeAbbreviation: String {
        normalizedGameType.abbreviation
    }
    
    /// Display string: variant if set, otherwise game format
    var displayVariant: String {
        if let v = variant, !v.isEmpty { return v }
        // Migrate old PLO sessions
        if gameType == .plo { return PokerVariant.plo.rawValue }
        return PokerVariant.noLimitHoldem.rawValue
    }
    
    /// Abbreviated variant for compact display (NLHE, PLO, PLO5, etc.)
    var displayVariantAbbreviation: String {
        Self.abbreviation(for: displayVariant)
    }
    
    /// Convert variant or game type string to abbreviation (NLHE, PLO, Cash, MTT, etc.)
    static func abbreviation(for variant: String) -> String {
        if let match = PokerVariant.allCases.first(where: { $0.rawValue == variant }) {
            return match.abbreviation
        }
        if let match = GameType.allCases.first(where: { $0.rawValue == variant }) {
            return match.abbreviation
        }
        return variant
    }
    
    static func formatCurrency(_ value: Double, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
    
    /// Compact format for calendars: <$100 shows 1 decimal if cents, $100–999 integer if whole, $1000+ uses K
    static func formatCompactCurrency(_ value: Double, currency: String = "USD") -> String {
        let absVal = abs(value)
        let symbol = currencySymbol(for: currency)
        let hasCents = absVal != floor(absVal)
        if absVal < 100 {
            return hasCents ? "\(symbol)\(String(format: "%.1f", absVal))" : "\(symbol)\(Int(absVal))"
        } else if absVal < 1000 {
            return hasCents ? "\(symbol)\(String(format: "%.2f", absVal))" : "\(symbol)\(Int(absVal))"
        } else {
            let k = absVal / 1000
            return k == floor(k) ? "\(symbol)\(Int(k))K" : "\(symbol)\(String(format: "%.1f", k))K"
        }
    }
    
    private static func currencySymbol(for code: String) -> String {
        switch code {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return "$"
        }
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
    
    var abbreviation: String {
        switch self {
        case .cash: return "Cash"
        case .plo: return "PLO"
        case .tournament: return "MTT"
        case .sitAndGo: return "SNG"
        case .homeGame: return "Home"
        case .online: return "Online"
        }
    }
    
    /// Formats shown in pickers (legacy PLO remains represented by Cash + variant)
    static var formatOptions: [GameType] {
        [.cash, .homeGame, .online, .tournament, .sitAndGo]
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
    
    var abbreviation: String {
        switch self {
        case .noLimitHoldem: return "NLHE"
        case .limitHoldem: return "LHE"
        case .plo: return "PLO"
        case .ploHiLo: return "PLO8"
        case .omahaHiLo: return "O8"
        case .fiveCardPlo: return "PLO5"
        case .sevenCardStud: return "7CS"
        case .studHiLo: return "Stud8"
        case .razz: return "Razz"
        case .tripleDraw: return "27TD"
        case .badugi: return "Badugi"
        case .shortDeck: return "6+"
        case .openFaceChinese: return "OFC"
        case .mixed: return "Mixed"
        }
    }
}

// MARK: - Session Tags
enum SessionTag: String, CaseIterable {
    case aGame = "A-Game"
    case tilt = "Tilt"
    case toughTable = "Tough Table"
    case softTable = "Soft Table"
    case badBeat = "Bad Beat"
    case runGood = "Run Good"
    case tired = "Tired"
    case focused = "Focused"
    case marathon = "Marathon"
    case confident = "Confident"
    case deepStack = "Deep Stack"
    case stressful = "Stressful"
    case profitable = "Profitable"
    case experimental = "Experimental"
    case bigBluff = "Big Bluff"

    var icon: String {
        switch self {
        case .aGame: return "star.fill"
        case .tilt: return "flame.fill"
        case .toughTable: return "shield.fill"
        case .softTable: return "leaf.fill"
        case .badBeat: return "bolt.fill"
        case .runGood: return "sparkles"
        case .tired: return "moon.fill"
        case .focused: return "eye.fill"
        case .marathon: return "clock.fill"
        case .confident: return "hand.thumbsup.fill"
        case .deepStack: return "arrow.up.right.circle.fill"
        case .stressful: return "exclamationmark.triangle.fill"
        case .profitable: return "dollarsign.circle.fill"
        case .experimental: return "flask.fill"
        case .bigBluff: return "theatermasks.fill"
        }
    }

    var color: Color {
        switch self {
        case .aGame:        return Color(red: 1.0, green: 0.75, blue: 0.0)   // gold
        case .tilt:         return Color(red: 0.95, green: 0.3, blue: 0.2)   // red-orange
        case .toughTable:   return Color(red: 0.55, green: 0.55, blue: 0.6)  // steel
        case .softTable:    return Color(red: 0.3, green: 0.78, blue: 0.45)  // green
        case .badBeat:      return Color(red: 0.85, green: 0.2, blue: 0.35)  // crimson
        case .runGood:      return Color(red: 0.2, green: 0.75, blue: 0.9)   // sky blue
        case .tired:        return Color(red: 0.5, green: 0.45, blue: 0.75)  // lavender
        case .focused:      return Color(red: 0.0, green: 0.6, blue: 0.85)   // blue
        case .marathon:     return Color(red: 0.6, green: 0.4, blue: 0.2)    // brown
        case .confident:    return Color(red: 0.95, green: 0.55, blue: 0.2)  // orange
        case .deepStack:    return Color(red: 0.25, green: 0.6, blue: 0.5)   // teal
        case .stressful:    return Color(red: 0.85, green: 0.65, blue: 0.15) // amber
        case .profitable:   return Color(red: 0.45, green: 0.8, blue: 0.3)   // lime
        case .experimental: return Color(red: 0.4, green: 0.45, blue: 0.85)  // indigo
        case .bigBluff:     return Color(red: 0.75, green: 0.3, blue: 0.7)   // purple
        }
    }
}

// MARK: - Stakes presets for quick-select buttons
enum StakesPreset: String, CaseIterable {
    case micro1 = ".1/.2"
    case micro2 = ".25/.50"
    case low1 = ".50/1"
    case mid1 = "2/5"
    case mid2 = "5/10"
    case high = "10/20"
    
    /// Symbol for currency code (USD->$, EUR->€, GBP->£)
    static func symbol(for currency: String) -> String {
        switch currency {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return "$"
        }
    }
    
    /// Stored value with currency symbol: X/Y format
    func storedValue(currency: String = "USD") -> String {
        let sym = Self.symbol(for: currency)
        switch self {
        case .micro1: return "\(sym)0.10/\(sym)0.20"
        case .micro2: return "\(sym)0.25/\(sym)0.50"
        case .low1: return "\(sym)0.50/\(sym)1"
        case .mid1: return "\(sym)2/\(sym)5"
        case .mid2: return "\(sym)5/\(sym)10"
        case .high: return "\(sym)10/\(sym)20"
        }
    }
}
