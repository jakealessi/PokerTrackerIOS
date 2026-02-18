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
    var startTime: Date?
    var endTime: Date?
    var imageIds: [String]
    
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
        handNotes: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        imageIds: [String] = []
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
        self.startTime = startTime
        self.endTime = endTime
        self.imageIds = imageIds
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
        startTime = try c.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        imageIds = try c.decodeIfPresent([String].self, forKey: .imageIds) ?? []
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
    
    /// Formats shown in pickers (excludes legacy PLO, homeGame, online)
    static var formatOptions: [GameType] {
        [.cash, .tournament, .sitAndGo]
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
