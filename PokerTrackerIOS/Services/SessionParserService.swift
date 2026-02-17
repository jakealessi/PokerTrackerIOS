//
//  SessionParserService.swift
//  PokerTrackerIOS
//
//  Free rule-based parser for natural language session descriptions.
//  No API key required - works offline.
//

import Foundation

enum SessionParserService {
    
    static func parse(_ text: String) -> ParsedSession? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return nil }
        
        guard let amount = parseAmount(from: lowercased) else { return nil }
        let hoursPlayed = parseHours(from: lowercased)
        let stakes = parseStakes(from: lowercased)
        let gameType = parseGameFormat(from: lowercased)
        let variant = parseVariant(from: lowercased)
        let venue = parseVenue(from: lowercased)
        
        return ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
            gameType: gameType,
            variant: variant,
            notes: nil,
            buyIn: nil,
            cashOut: nil,
            date: nil,
            tournamentPosition: nil,
            rebuys: nil,
            handNotes: nil
        )
    }
    
    // MARK: - Amount
    
    private static func parseAmount(from text: String) -> Double? {
        let winPatterns = [
            #"won\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"up\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"profit\s+(?:of\s+)?\$?([\d,]+(?:\.\d+)?)"#,
            #"profitability\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"cashed\s+(?:for\s+)?\$?([\d,]+(?:\.\d+)?)"#,
            #"^\s*\+\s*\$?([\d,]+(?:\.\d+)?)"#,
            #"\+?\$?([\d,]+(?:\.\d+)?)\s*(?:profit|won|up)"#
        ]
        
        for pattern in winPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let substr = String(text[match])
                if let num = extractNumber(from: substr) { return num }
            }
        }
        
        let lossPatterns = [
            #"lost\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"down\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"loss\s+(?:of\s+)?\$?([\d,]+(?:\.\d+)?)"#,
            #"^\s*-\s*\$?([\d,]+(?:\.\d+)?)"#,
            #"-\$?([\d,]+(?:\.\d+)?)\s*(?:loss|lost|down)"#
        ]
        
        for pattern in lossPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let substr = String(text[match])
                if let num = extractNumber(from: substr) { return -num }
            }
        }
        
        let numberPattern = #"\$?([\d,]+(?:\.\d+)?)"#
        if let match = text.range(of: numberPattern, options: .regularExpression) {
            let substr = String(text[match])
            if let num = extractNumber(from: substr), num > 0 {
                if text.contains("lost") || text.contains("down") || text.contains("loss") {
                    return -num
                }
                return num
            }
        }
        
        return nil
    }
    
    private static func extractNumber(from str: String) -> Double? {
        let cleaned = str.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }
    
    // MARK: - Hours
    
    private static func parseHours(from text: String) -> Double? {
        let timeRangePattern = #"(\d{1,2})\s*(am|pm)\s*(?:to|-|–)\s*(\d{1,2})\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: timeRangePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text),
           let r3 = Range(match.range(at: 3), in: text),
           let r4 = Range(match.range(at: 4), in: text),
           let startNum = Int(text[r1]), let endNum = Int(text[r3]) {
            let startPeriod = String(text[r2])
            let endPeriod = String(text[r4])
            func to24h(_ n: Int, _ p: String) -> Int {
                if p == "am" { return n == 12 ? 0 : n }
                return n == 12 ? 12 : n + 12
            }
            let startH = to24h(startNum, startPeriod)
            let endH = to24h(endNum, endPeriod)
            let hours = endH > startH ? endH - startH : (24 - startH) + endH
            return Double(hours)
        }
        
        let hoursPattern = #"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h\b)"#
        if let regex = try? NSRegularExpression(pattern: hoursPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text),
           let h = Double(text[r]) {
            return h
        }
        
        let simpleRange = #"(\d{1,2})\s*(?:to|-)\s*(\d{1,2})"#
        if let regex = try? NSRegularExpression(pattern: simpleRange),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text),
           let start = Int(text[r1]), let end = Int(text[r2]) {
            var s = start
            var e = end
            if text.contains("pm") && s < 12 { s += 12 }
            if text.contains("am") && e < 12 && e > s { s += 12; e += 12 }
            let hours = Double((e - s + 24) % 24)
            return hours > 0 && hours < 24 ? hours : nil
        }
        
        return nil
    }
    
    // MARK: - Stakes
    
    private static func parseStakes(from text: String) -> String? {
        let stakesPattern = #"\$?(\d+(?:\.\d+)?)\s*[/\-]\s*\$?(\d+(?:\.\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: stakesPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text) {
            return "$\(text[r1])/$\(text[r2])"
        }
        return nil
    }
    
    // MARK: - Game Format
    
    private static func parseGameFormat(from text: String) -> GameType {
        if text.contains("tournament") || text.contains("mtt") { return .tournament }
        if text.contains("sit") && (text.contains("go") || text.contains("n go")) { return .sitAndGo }
        if text.contains("home game") { return .homeGame }
        if text.contains("online") { return .online }
        return .cash
    }
    
    // MARK: - Variant
    
    private static func parseVariant(from text: String) -> String? {
        if text.contains("plo hi") || text.contains("plo h/l") || text.contains("omaha hi-lo") || text.contains("omaha hi lo") {
            return PokerVariant.ploHiLo.rawValue
        }
        if text.contains("plo") || text.contains("pot limit omaha") || text.contains("omaha") {
            return PokerVariant.plo.rawValue
        }
        if text.contains("5 card") || text.contains("five card") || text.contains("5-card") {
            return PokerVariant.fiveCardPlo.rawValue
        }
        if text.contains("stud hi") || text.contains("stud h/l") {
            return PokerVariant.studHiLo.rawValue
        }
        if text.contains("stud") || text.contains("seven card") {
            return PokerVariant.sevenCardStud.rawValue
        }
        if text.contains("razz") {
            return PokerVariant.razz.rawValue
        }
        if text.contains("triple draw") || text.contains("2-7") {
            return PokerVariant.tripleDraw.rawValue
        }
        if text.contains("badugi") {
            return PokerVariant.badugi.rawValue
        }
        if text.contains("short deck") || text.contains("6+") || text.contains("six plus") {
            return PokerVariant.shortDeck.rawValue
        }
        if text.contains("open face") || text.contains("ofc") || text.contains("chinese") {
            return PokerVariant.openFaceChinese.rawValue
        }
        if text.contains("mixed") || text.contains("horse") || text.contains("h.o.r.s.e") {
            return PokerVariant.mixed.rawValue
        }
        if text.contains("limit hold") || (text.contains("limit") && text.contains("hold") && !text.contains("no limit")) {
            return PokerVariant.limitHoldem.rawValue
        }
        if text.contains("hold'em") || text.contains("holdem") || text.contains("hold em") || text.contains("nlh") || text.contains("no limit") {
            return PokerVariant.noLimitHoldem.rawValue
        }
        return nil
    }
    
    // MARK: - Venue
    
    private static func parseVenue(from text: String) -> String? {
        let atPattern = #"at\s+(?:the\s+)?([a-zA-Z0-9\s]+?)(?:\s+and|\s+from|\.|$)"#
        if let regex = try? NSRegularExpression(pattern: atPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            let venue = String(text[r]).trimmingCharacters(in: .whitespaces)
            return venue.count > 2 ? venue : nil
        }
        return nil
    }
}
