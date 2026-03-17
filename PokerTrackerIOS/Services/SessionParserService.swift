//
//  SessionParserService.swift
//  PokerTrackerIOS
//
//  Free rule-based parser for natural language session descriptions.
//  No API key required - works offline.
//

import Foundation

enum SessionParserService {

    static func parseHoursValue(from text: String) -> Double? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return parseHours(from: normalized)
    }

    static func parseDateValue(from text: String, relativeTo referenceDate: Date = Date()) -> Date? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return parseDate(from: normalized, relativeTo: referenceDate)
    }
    
    static func parse(_ text: String, relativeTo referenceDate: Date = Date()) -> ParsedSession? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return nil }
        
        guard let amount = parseAmount(from: lowercased) else { return nil }
        let hoursPlayed = parseHoursValue(from: lowercased)
        let stakes = parseStakes(from: lowercased)
        let gameType = parseGameFormat(from: lowercased)
        let variant = parseVariant(from: lowercased)
        let venue = parseVenue(from: lowercased)
        let date = parseDate(from: lowercased, relativeTo: referenceDate)
        
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
            date: date,
            tournamentPosition: nil,
            rebuys: nil,
            handNotes: nil,
            tags: []
        )
    }
    
    // MARK: - Amount
    
    private static func parseAmount(from text: String) -> Double? {
        if let derived = parseNetFromBuyInAndCashOut(from: text) {
            return derived
        }

        let winPatterns = [
            #"won\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"made\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"booked\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"up\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"profit\s+(?:of\s+)?\$?([\d,]+(?:\.\d+)?)"#,
            #"profitability\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"^\s*\+\s*\$?([\d,]+(?:\.\d+)?)"#,
            #"\+?\$?([\d,]+(?:\.\d+)?)\s*(?:profit|won|up|made|booked)"#
        ]
        
        for pattern in winPatterns {
            if let num = extractNumber(using: pattern, in: text) { return num }
        }
        
        let lossPatterns = [
            #"lost\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"down\s+\$?([\d,]+(?:\.\d+)?)"#,
            #"loss\s+(?:of\s+)?\$?([\d,]+(?:\.\d+)?)"#,
            #"^\s*-\s*\$?([\d,]+(?:\.\d+)?)"#,
            #"-\$?([\d,]+(?:\.\d+)?)\s*(?:loss|lost|down)"#
        ]
        
        for pattern in lossPatterns {
            if let num = extractNumber(using: pattern, in: text) { return -num }
        }
        
        return nil
    }

    private static func parseNetFromBuyInAndCashOut(from text: String) -> Double? {
        let buyInPattern = #"(?:buy(?:\s|-)?in|bought\s*in)\s*(?:for\s*)?\$?([\d,]+(?:\.\d+)?)"#
        let cashOutPattern = #"(?:cash(?:ed)?\s*out|cashed|cashout)\s*(?:for\s*)?\$?([\d,]+(?:\.\d+)?)"#

        guard
            let buyIn = extractNumber(using: buyInPattern, in: text),
            let cashOut = extractNumber(using: cashOutPattern, in: text)
        else {
            return nil
        }

        return cashOut - buyIn
    }

    private static func extractNumber(using pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let numeric = text[range]
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(numeric)
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
        
        let simpleRange = #"(\d{1,2})(?:\s*(am|pm))?\s*(?:to|-|–)\s*(\d{1,2})(?:\s*(am|pm))?"#
        if let regex = try? NSRegularExpression(pattern: simpleRange),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 3), in: text),
           let start = Int(text[r1]), let end = Int(text[r2]) {
            let startPeriod = extractOptionalMatch(match, at: 2, in: text)
            let endPeriod = extractOptionalMatch(match, at: 4, in: text)
            return inferredHourSpan(
                startHour: start,
                startPeriod: startPeriod,
                endHour: end,
                endPeriod: endPeriod
            )
        }
        
        return nil
    }

    // MARK: - Date

    private static func parseDate(from text: String, relativeTo referenceDate: Date) -> Date? {
        let calendar = Calendar.current

        if text.contains("today") {
            return referenceDate
        }
        if text.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: referenceDate)
        }
        if let daysAgo = extractInt(using: #"(\d+)\s+days?\s+ago"#, in: text) {
            return calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate)
        }
        if let weeksAgo = extractInt(using: #"(\d+)\s+weeks?\s+ago"#, in: text) {
            return calendar.date(byAdding: .day, value: -(weeksAgo * 7), to: referenceDate)
        }
        if text.contains("last weekend") || text.contains("this past weekend") {
            return mostRecentWeekday(7, before: referenceDate, using: calendar)
        }
        if let weekdayDate = parseRelativeWeekday(from: text, relativeTo: referenceDate, using: calendar) {
            return weekdayDate
        }
        if let absoluteDate = parseAbsoluteDate(from: text, relativeTo: referenceDate, using: calendar) {
            return absoluteDate
        }

        return nil
    }
    
    // MARK: - Stakes
    
    private static func parseStakes(from text: String) -> String? {
        let stakesPattern = #"\$?((?:\d+(?:\.\d+)?)|(?:\.\d+))\s*[/\-]\s*\$?((?:\d+(?:\.\d+)?)|(?:\.\d+))"#
        if let regex = try? NSRegularExpression(pattern: stakesPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text) {
            let smallBlind = normalizeStakeComponent(String(text[r1]))
            let bigBlind = normalizeStakeComponent(String(text[r2]))
            return "$\(smallBlind)/$\(bigBlind)"
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
        if text.contains("5 card") || text.contains("five card") || text.contains("5-card") {
            return PokerVariant.fiveCardPlo.rawValue
        }
        if text.contains("plo") || text.contains("pot limit omaha") || text.contains("omaha") {
            return PokerVariant.plo.rawValue
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
        let atPattern = #"at\s+(?:the\s+)?([a-zA-Z0-9][a-zA-Z0-9&'’\-\.\s]*?)(?:\s+and|\s+from|\s+for|,|\.|$)"#
        if let regex = try? NSRegularExpression(pattern: atPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            let venue = String(text[r]).trimmingCharacters(in: .whitespaces)
            return venue.count > 2 ? VenueCleaner.clean(venue) : nil
        }
        return nil
    }

    private static func extractInt(using pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func extractOptionalMatch(_ match: NSTextCheckingResult, at index: Int, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func inferredHourSpan(
        startHour: Int,
        startPeriod: String?,
        endHour: Int,
        endPeriod: String?
    ) -> Double? {
        let starts = hourCandidates(for: startHour, period: startPeriod)
        let ends = hourCandidates(for: endHour, period: endPeriod)

        let duration = starts
            .flatMap { start in
                ends.map { end in
                    (end - start + 24) % 24
                }
            }
            .filter { $0 > 0 && $0 < 24 }
            .min()

        return duration.map(Double.init)
    }

    private static func hourCandidates(for hour: Int, period: String?) -> [Int] {
        guard (0...23).contains(hour) else { return [] }

        if let period {
            guard hour <= 12 else { return [] }
            let normalized = hour == 12 ? 0 : hour
            if period == "am" {
                return [normalized]
            }
            return [normalized == 0 ? 12 : normalized + 12]
        }

        if hour == 12 {
            return [0, 12]
        }
        if hour < 12 {
            return [hour, hour + 12]
        }
        return [hour]
    }

    private static func parseRelativeWeekday(from text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        let pattern = #"(?:last|this past)\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let weekdayMap: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]
        guard let weekday = weekdayMap[String(text[range])] else { return nil }
        return mostRecentWeekday(weekday, before: referenceDate, using: calendar)
    }

    private static func mostRecentWeekday(_ weekday: Int, before referenceDate: Date, using calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        var daysBack = (currentWeekday - weekday + 7) % 7
        if daysBack == 0 {
            daysBack = 7
        }
        return calendar.date(byAdding: .day, value: -daysBack, to: referenceDate)
    }

    private static func parseAbsoluteDate(from text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        if let isoDate = extractMatch(using: #"\b(\d{4}-\d{1,2}-\d{1,2})\b"#, in: text) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: isoDate)
        }

        if let slashDate = parseSlashDate(
            using: #"\b(\d{1,2})\/(\d{1,2})\/(\d{2,4})\b"#,
            in: text,
            relativeTo: referenceDate,
            using: calendar
        ) {
            return slashDate
        }

        return parseSlashDate(
            using: #"(?:\bon\b|\bdate\b)\s+(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b"#,
            in: text,
            relativeTo: referenceDate,
            using: calendar
        )
    }

    private static func parseSlashDate(using pattern: String, in text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange]) else {
            return nil
        }

        let year: Int
        if let yearRange = Range(match.range(at: 3), in: text), !yearRange.isEmpty, let explicitYear = Int(text[yearRange]) {
            year = explicitYear < 100 ? 2000 + explicitYear : explicitYear
        } else {
            year = calendar.component(.year, from: referenceDate)
        }

        var components = calendar.dateComponents([.hour, .minute, .second], from: referenceDate)
        components.year = year
        components.month = month
        components.day = day

        guard let parsedDate = calendar.date(from: components) else { return nil }
        if parsedDate <= referenceDate || Range(match.range(at: 3), in: text) != nil {
            return parsedDate
        }

        return calendar.date(byAdding: .year, value: -1, to: parsedDate)
    }

    private static func extractMatch(using pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func normalizeStakeComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix(".") {
            return "0" + trimmed
        }
        return trimmed
    }
}
