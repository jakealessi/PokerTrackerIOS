//
//  SessionParserService.swift
//  PokerTrackerIOS
//
//  Free rule-based parser for natural language session descriptions.
//  No API key required - works offline.
//

import Foundation

enum SessionParserService {
    struct ExtractedSessionSignals {
        let hoursPlayed: Double?
        let stakes: String?
        let gameType: GameType?
        let variant: String?
        let venue: String?
        let rake: Double?
        let tips: Double?
        let food: Double?
        let travel: Double?
        let fees: Double?
        let buyIn: Double?
        let cashOut: Double?
        let date: Date?
        let tournamentPosition: Int?
        let buyins: Int?
    }

    private struct AmountCandidate {
        let value: Double
        let priority: Int
        let location: Int
    }

    private static let supportedCurrencySymbols: [String] = Array(Set(SupportedCurrency.all.map { $0.symbol.lowercased() }))
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs > rhs
        }
    private static let supportedCurrencyCodes: [String] = Array(Set(SupportedCurrency.all.map { $0.code.lowercased() }))
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs > rhs
        }
    private static let supportedCurrencyTokens: [String] = Array(Set(supportedCurrencySymbols + supportedCurrencyCodes))
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs > rhs
        }
    private static let optionalCurrencyPrefixPattern: String = {
        let escapedTokens = supportedCurrencyTokens.map { NSRegularExpression.escapedPattern(for: $0) }
        return "(?:(?:\(escapedTokens.joined(separator: "|")))\\s*)?"
    }()
    private static let stakeComponentPattern = #"(?:\d+(?:\.\d+)?|\.\d+)"#
    private static let stakesPairPattern = "\(optionalCurrencyPrefixPattern)(\(stakeComponentPattern))\\s*[/\\-]\\s*\(optionalCurrencyPrefixPattern)(\(stakeComponentPattern))"
    private static let stakesTriplePattern = "\(optionalCurrencyPrefixPattern)(\(stakeComponentPattern))\\s*[/\\-]\\s*\(optionalCurrencyPrefixPattern)(\(stakeComponentPattern))\\s*[/\\-]\\s*\(optionalCurrencyPrefixPattern)(\(stakeComponentPattern))"
    private static let numberCapturePattern = #"(\(?[+\-]?\s*"# + optionalCurrencyPrefixPattern + #"[\d,]+(?:\.\d+)?[kKmM]?\)?)"#

    static func parseNumericValue(from text: String) -> Double? {
        var cleaned = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        if ["null", "nil", "none", "n/a", "na"].contains(cleaned) {
            return nil
        }

        let negativeByParentheses = cleaned.hasPrefix("(") && cleaned.hasSuffix(")")
        cleaned = cleaned
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ",", with: "")

        for symbol in supportedCurrencySymbols {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }

        for code in supportedCurrencyCodes {
            cleaned = cleaned.replacingOccurrences(of: code, with: "")
        }

        cleaned = cleaned.replacingOccurrences(of: " ", with: "")

        var multiplier = 1.0
        if cleaned.hasSuffix("k") {
            multiplier = 1_000
            cleaned.removeLast()
        } else if cleaned.hasSuffix("m") {
            multiplier = 1_000_000
            cleaned.removeLast()
        }

        let negativeByPrefix = cleaned.hasPrefix("-")
        if cleaned.hasPrefix("+") || cleaned.hasPrefix("-") {
            cleaned.removeFirst()
        }

        guard let base = Double(cleaned) else { return nil }
        let value = base * multiplier
        return (negativeByParentheses || negativeByPrefix) ? -value : value
    }

    static func parseOrdinalValue(from text: String) -> Int? {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let digits = extractMatch(using: #"\b(\d+)(?:st|nd|rd|th)?\b"#, in: trimmed),
           let value = Int(digits) {
            return value
        }

        let words: [String: Int] = [
            "zero": 0,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
            "first": 1,
            "second": 2,
            "third": 3,
            "fourth": 4,
            "fifth": 5,
            "sixth": 6,
            "seventh": 7,
            "eighth": 8,
            "ninth": 9,
            "tenth": 10,
            "eleventh": 11,
            "twelfth": 12
        ]

        return words[trimmed]
    }

    static func parseWholeNumberValue(from text: String) -> Int? {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let numeric = parseNumericValue(from: trimmed) {
            guard numeric.isFinite,
                  numeric.rounded(.towardZero) == numeric,
                  numeric >= Double(Int.min),
                  numeric <= Double(Int.max) else {
                return nil
            }
            return Int(numeric)
        }

        let exactOrdinalWords: [String: Int] = [
            "zero": 0,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
            "first": 1,
            "second": 2,
            "third": 3,
            "fourth": 4,
            "fifth": 5,
            "sixth": 6,
            "seventh": 7,
            "eighth": 8,
            "ninth": 9,
            "tenth": 10,
            "eleventh": 11,
            "twelfth": 12
        ]

        return exactOrdinalWords[trimmed]
    }

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

    static func parseGameTypeValue(from text: String) -> GameType? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let exact = GameType.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            return exact
        }
        return parseGameFormat(from: normalized)
    }

    static func parseVariantValue(from text: String) -> String? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return parseVariant(from: normalized)
    }

    static func extractSignals(from text: String, relativeTo referenceDate: Date = Date()) -> ExtractedSessionSignals? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        return ExtractedSessionSignals(
            hoursPlayed: parseHours(from: normalized),
            stakes: parseStakes(from: normalized),
            gameType: parseGameFormat(from: normalized),
            variant: parseVariant(from: normalized),
            venue: parseVenue(from: normalized),
            rake: parseExpense(from: normalized, patterns: rakePatterns),
            tips: parseExpense(from: normalized, patterns: tipsPatterns),
            food: parseExpense(from: normalized, patterns: foodPatterns),
            travel: parseExpense(from: normalized, patterns: travelPatterns),
            fees: parseExpense(from: normalized, patterns: feesPatterns),
            buyIn: parseBuyIn(from: normalized),
            cashOut: parseCashOut(from: normalized),
            date: parseDate(from: normalized, relativeTo: referenceDate),
            tournamentPosition: parseTournamentPosition(from: normalized),
            buyins: parseBuyins(from: normalized)
        )
    }
    
    static func parse(_ text: String, relativeTo referenceDate: Date = Date()) -> ParsedSession? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return nil }
        guard let signals = extractSignals(from: lowercased, relativeTo: referenceDate) else { return nil }
        guard let amount = parseAmount(from: lowercased, buyIn: signals.buyIn, cashOut: signals.cashOut, buyins: signals.buyins) else { return nil }

        return ParsedSession(
            amount: amount,
            hoursPlayed: signals.hoursPlayed,
            stakes: signals.stakes,
            venue: signals.venue,
            rake: signals.rake,
            tips: signals.tips,
            food: signals.food,
            travel: signals.travel,
            fees: signals.fees,
            gameType: signals.gameType ?? .cash,
            variant: signals.variant,
            notes: nil,
            buyIn: signals.buyIn,
            cashOut: signals.cashOut,
            date: signals.date,
            tournamentPosition: signals.tournamentPosition,
            buyins: signals.buyins,
            handNotes: nil,
            tags: []
        )
    }
    
    // MARK: - Amount
    
    private static func parseAmount(from text: String, buyIn: Double?, cashOut: Double?, buyins: Int?) -> Double? {
        let effectiveBuyins = buyins ?? 1
        if let buyIn, let cashOut, effectiveBuyins > 0 {
            return cashOut - (buyIn * Double(effectiveBuyins))
        }
        var candidates: [AmountCandidate] = []

        appendAmountMatches(
            using: [
                "(?:^|[\\s,;])(?:won|made|booked|netted|profited)\\s+\(numberCapturePattern)",
                "(?:^|[\\s,;])(?:finished|ended|left)(?:\\s+the\\s+(?:session|night|day))?\\s+(?:up|ahead)\\s+\(numberCapturePattern)",
                "(?:^|[\\s,;])profit(?:\\s+of|\\s+was)?\\s+\(numberCapturePattern)",
                "^\\s*\\+\\s*\(numberCapturePattern)",
                "\\b\(numberCapturePattern)\\s*(?:profit|won|made|booked|up)\\b"
            ],
            in: text,
            priority: 120,
            transform: { abs($0) },
            into: &candidates,
            shouldFilterMidSession: false
        )

        appendAmountMatches(
            using: [
                "(?:^|[\\s,;])(?:lost|dropped|dumped|dusted)\\s+\(numberCapturePattern)",
                "(?:^|[\\s,;])loss(?:\\s+of|\\s+was)?\\s+\(numberCapturePattern)",
                "(?:^|[\\s,;])(?:finished|ended|left)(?:\\s+the\\s+(?:session|night|day))?\\s+down\\s+\(numberCapturePattern)",
                "^\\s*-\\s*\(numberCapturePattern)",
                "\\b\(numberCapturePattern)\\s*(?:loss|lost|down)\\b"
            ],
            in: text,
            priority: 120,
            transform: { -abs($0) },
            into: &candidates,
            shouldFilterMidSession: false
        )

        appendAmountMatches(
            using: [
                "(?:^|[\\s,;])up\\s+\(numberCapturePattern)",
                "(?:^|[\\s,;])finished\\s+\(numberCapturePattern)\\s+ahead\\b"
            ],
            in: text,
            priority: 90,
            transform: { abs($0) },
            into: &candidates
        )

        appendAmountMatches(
            using: [
                "(?:^|[\\s,;])(?:down|stuck)\\s+\(numberCapturePattern)"
            ],
            in: text,
            priority: 90,
            transform: { -abs($0) },
            into: &candidates
        )

        appendFixedAmountMatches(
            using: [
                #"(?:^|[\s,;])(?:(?:broke|break)\s+even|break-even|breakeven)\b"#,
                #"(?:^|[\s,;])(?:finished|ended|left)(?:\s+the\s+(?:session|night|day))?\s+(?:even|flat)\b"#,
                #"(?:^|[\s,;])(?:was|stayed)\s+(?:even|flat)(?:$|[.,;])"#,
                #"(?:^|[\s,;])(?:was|stayed)\s+(?:even|flat)\s+(?:for|on)\s+the\s+(?:session|night|day)\b"#,
                #"(?:^|[\s,;])flat\s+for\s+the\s+(?:session|night|day)\b"#
            ],
            in: text,
            priority: 110,
            value: 0,
            into: &candidates
        )

        appendAmountMatches(
            using: [
                "(?:^|[\\s,;])(\\+\\s*\(optionalCurrencyPrefixPattern)[\\d,]+(?:\\.\\d+)?[kKmM]?)\\b",
                "(?:^|[\\s,;])(\\-\\s*\(optionalCurrencyPrefixPattern)[\\d,]+(?:\\.\\d+)?[kKmM]?)\\b"
            ],
            in: text,
            priority: 100,
            transform: { $0 },
            into: &candidates,
            shouldFilterMidSession: false
        )

        if let best = candidates.sorted(by: compareAmountCandidates).first {
            return best.value
        }

        return nil
    }

    private static func parseExpense(from text: String, patterns: [String]) -> Double? {
        var total = 0.0
        var seenRanges = Set<String>()

        for pattern in patterns {
            for match in extractNumbers(using: pattern, in: text) {
                let key = "\(match.range.location)-\(match.range.length)"
                guard seenRanges.insert(key).inserted else { continue }
                total += abs(match.value)
            }
        }

        return total > 0.0001 ? total : nil
    }
    
    // MARK: - Hours
    
    private static func parseHours(from text: String) -> Double? {
        if let timeRangeHours = parseClockTimeRange(from: text) {
            return timeRangeHours
        }

        let hoursMinutesPattern = #"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|hr|h)\s*(\d{1,2})\s*(?:minutes?|mins?|min|m)\b"#
        if let (hours, minutes) = extractTwoNumbers(using: hoursMinutesPattern, in: text) {
            return hours + (minutes / 60)
        }

        if let hours = extractFlexibleNumber(using: #"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|hr|h)\b"#, in: text) {
            return hours
        }

        if let minutes = extractFlexibleNumber(using: #"(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|min)\b"#, in: text) {
            return minutes / 60
        }

        if let minutes = extractFlexibleNumber(
            using: #"\b(?:for|played|lasting|lasted|over|about|around|roughly|just|only)\s+(\d+(?:\.\d+)?)\s*m\b"#,
            in: text
        ) {
            return minutes / 60
        }

        if let bareMinutes = parseBareMinutesDuration(from: text) {
            return bareMinutes
        }

        if text.contains("half hour") || text.contains("half an hour") {
            return 0.5
        }
        
        return nil
    }

    // MARK: - Date

    private static func parseDate(from text: String, relativeTo referenceDate: Date) -> Date? {
        let calendar = Calendar.current

        if text.contains("today") || text.contains("tonight") || text.contains("this morning") || text.contains("this afternoon") || text.contains("this evening") {
            return referenceDate
        }
        if text.contains("last night") {
            return calendar.date(byAdding: .day, value: -1, to: referenceDate)
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
        if let monthsAgo = extractInt(using: #"(\d+)\s+months?\s+ago"#, in: text) {
            return calendar.date(byAdding: .month, value: -monthsAgo, to: referenceDate)
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
        if let tripleRegex = try? NSRegularExpression(pattern: stakesTriplePattern) {
            let tripleMatches = tripleRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in tripleMatches {
                guard let r1 = Range(match.range(at: 1), in: text),
                      let r2 = Range(match.range(at: 2), in: text),
                      let r3 = Range(match.range(at: 3), in: text) else {
                    continue
                }
                let fullText = (text as NSString).substring(with: match.range(at: 0))
                guard isLikelyStakesExpression(fullText, matchRange: match.range(at: 0), in: text) else {
                    continue
                }
                let smallBlind = normalizeStakeComponent(String(text[r1]))
                let bigBlind = normalizeStakeComponent(String(text[r2]))
                let straddle = normalizeStakeComponent(String(text[r3]))
                let currencyCode = resolvedStakeCurrencyCode(from: fullText) ?? "USD"
                return formatStakesOutput(small: smallBlind, big: bigBlind, straddle: straddle, currencyCode: currencyCode)
            }
        }
        if let pairRegex = try? NSRegularExpression(pattern: stakesPairPattern) {
            let pairMatches = pairRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in pairMatches {
                guard let r1 = Range(match.range(at: 1), in: text),
                      let r2 = Range(match.range(at: 2), in: text) else {
                    continue
                }
                let fullText = (text as NSString).substring(with: match.range(at: 0))
                guard isLikelyStakesExpression(fullText, matchRange: match.range(at: 0), in: text) else {
                    continue
                }
                let smallBlind = normalizeStakeComponent(String(text[r1]))
                let bigBlind = normalizeStakeComponent(String(text[r2]))
                let currencyCode = resolvedStakeCurrencyCode(from: fullText) ?? "USD"
                return formatStakesOutput(small: smallBlind, big: bigBlind, straddle: "", currencyCode: currencyCode)
            }
        }
        return nil
    }
    
    // MARK: - Game Format
    
    private static func parseGameFormat(from text: String) -> GameType? {
        if containsAnyPattern(in: text, patterns: [#"\btournament\b"#, #"\bmtt\b"#, #"\bring event\b"#]) {
            return .tournament
        }
        if containsAnyPattern(in: text, patterns: [#"\bsng\b"#, #"\bsit\s*(?:and|n)?\s*go\b"#, #"\bspin\s*(?:and|n)?\s*go\b"#]) {
            return .sitAndGo
        }
        if containsAnyPattern(in: text, patterns: [#"\bhome game\b"#]) {
            return .homeGame
        }
        if containsAnyPattern(in: text, patterns: [#"\bonline\b"#]) {
            return .online
        }
        if containsAnyPattern(in: text, patterns: [#"\bcash(?:\s+game)?\b"#, #"\bring\s+game\b"#]) {
            return .cash
        }
        return nil
    }
    
    // MARK: - Variant
    
    private static func parseVariant(from text: String) -> String? {
        if containsAnyPattern(in: text, patterns: [#"\bo8\b"#, #"\bomaha\s*8\b"#, #"\bomaha\s+hi[\s-]*lo\b"#]) {
            return PokerVariant.omahaHiLo.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bplo\s+hi\b"#, #"\bplo\s*h/l\b"#, #"\bplo\s+hi[\s-]*lo\b"#]) {
            return PokerVariant.ploHiLo.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bplo5\b"#, #"\bplo\s*5\b"#, #"\b(?:5|five)[\s-]*card\s+(?:plo|omaha)\b"#, #"\b(?:plo|omaha)\s*(?:5|five)[\s-]*card\b"#]) {
            return PokerVariant.fiveCardPlo.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bplo\b"#, #"\bpot\s+limit\s+omaha\b"#, #"(?<!at )(?<!in )(?<!to )(?<!from )\bomaha\b"#]) {
            return PokerVariant.plo.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bstud\s+hi\b"#, #"\bstud\s*h/l\b"#, #"\bstud\s+hi[\s-]*lo\b"#]) {
            return PokerVariant.studHiLo.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bstud\b"#, #"\b(?:seven|7)[\s-]*card\s+stud\b"#]) {
            return PokerVariant.sevenCardStud.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\brazz\b"#]) {
            return PokerVariant.razz.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\btriple\s+draw\b"#, #"\bdeuce[\s-]*to[\s-]*seven\b"#, #"\b2[\s-]*7\s+triple\s+draw\b"#, #"\b2[\s-]*7\s+lowball\b"#]) {
            return PokerVariant.tripleDraw.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bbadugi\b"#]) {
            return PokerVariant.badugi.rawValue
        }
        if isShortDeckMention(in: text) {
            return PokerVariant.shortDeck.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bopen\s+face(?:\s+chinese)?\b"#, #"\bofc\b"#]) {
            return PokerVariant.openFaceChinese.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\bmixed\s+games?\b"#, #"\bmix(?:ed)?\s+game\b"#, #"\bhorse\b"#, #"\bh\.o\.r\.s\.e\b"#, #"\b8-game\b"#]) {
            return PokerVariant.mixed.rawValue
        }
        if containsAnyPattern(in: text, patterns: [#"\blimit\s+hold(?:'em|em|\s+em)?\b"#, #"\blhe\b"#]) {
            return PokerVariant.limitHoldem.rawValue
        }
        if containsAnyPattern(
            in: text,
            patterns: [
                #"\bhold(?:'em|em|\s+em)\b"#,
                #"\bnlh\b"#,
                #"\bno\s+limit\s+hold(?:'em|em|\s+em)?\b"#,
                #"\bhold(?:'em|em|\s+em)?\s+no\s+limit\b"#
            ]
        ) {
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
            let venue = trimTrailingVenueNoise(String(text[r]))
            guard venue.count > 2, isLikelyVenue(venue) else { return nil }
            return VenueCleaner.clean(venue)
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
        return parseOrdinalValue(from: String(text[range]))
    }

    private static func extractOptionalMatch(_ match: NSTextCheckingResult, at index: Int, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func inferredMinuteSpan(
        startHour: Int,
        startMinute: Int,
        startPeriod: String?,
        endHour: Int,
        endMinute: Int,
        endPeriod: String?
    ) -> Double? {
        let starts = minuteCandidates(for: startHour, minute: startMinute, period: startPeriod)
        let ends = minuteCandidates(for: endHour, minute: endMinute, period: endPeriod)

        let duration = starts
            .flatMap { start in
                ends.map { end in
                    (end - start + 24 * 60) % (24 * 60)
                }
            }
            .filter { $0 > 0 && $0 < 24 * 60 }
            .min()

        return duration.map { Double($0) / 60 }
    }

    private static func minuteCandidates(for hour: Int, minute: Int, period: String?) -> [Int] {
        guard (0...23).contains(hour) else { return [] }
        guard (0...59).contains(minute) else { return [] }

        if let period {
            guard hour <= 12 else { return [] }
            let normalized = hour == 12 ? 0 : hour
            if period == "am" {
                return [normalized * 60 + minute]
            }
            let mappedHour = normalized == 0 ? 12 : normalized + 12
            return [mappedHour * 60 + minute]
        }

        if hour == 12 {
            return [minute, 12 * 60 + minute]
        }
        if hour < 12 {
            return [hour * 60 + minute, (hour + 12) * 60 + minute]
        }
        return [hour * 60 + minute]
    }

    private static func parseRelativeWeekday(from text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        let weekdayMap: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]

        if let weekdayName = extractMatch(
            using: #"(?:last|this past)\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)"#,
            in: text
        ), let weekday = weekdayMap[weekdayName] {
            return mostRecentWeekday(weekday, before: referenceDate, using: calendar)
        }

        if let weekdayName = extractMatch(
            using: #"(?:\bon\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?:\s+(?:night|morning|afternoon|evening))?\b"#,
            in: text
        ), let weekday = weekdayMap[weekdayName] {
            return mostRecentOrSameWeekday(weekday, relativeTo: referenceDate, using: calendar)
        }

        return nil
    }

    private static func mostRecentWeekday(_ weekday: Int, before referenceDate: Date, using calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        var daysBack = (currentWeekday - weekday + 7) % 7
        if daysBack == 0 {
            daysBack = 7
        }
        return calendar.date(byAdding: .day, value: -daysBack, to: referenceDate)
    }

    private static func mostRecentOrSameWeekday(_ weekday: Int, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        let daysBack = (currentWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: referenceDate)
    }

    private static func parseAbsoluteDate(from text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        if let isoDate = extractMatch(using: #"\b(\d{4}-\d{1,2}-\d{1,2})\b"#, in: text) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
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

        if let monthNameDate = parseMonthNameDate(from: text, relativeTo: referenceDate, using: calendar) {
            return monthNameDate
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
        let explicitYearText = extractOptionalMatch(match, at: 3, in: text)
        if let explicitYearText, let explicitYear = Int(explicitYearText) {
            guard isLikelyExplicitSlashDate(
                month: month,
                day: day,
                explicitYear: explicitYearText,
                matchRange: match.range(at: 0),
                in: text
            ) else {
                return nil
            }
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

    private static func isLikelyExplicitSlashDate(month: Int, day: Int, explicitYear: String, matchRange: NSRange, in text: String) -> Bool {
        if explicitYear.count >= 4 || day > 12 {
            return true
        }

        let context = surroundingContext(for: matchRange, in: text, window: 28)
        let datePatterns = [
            #"\bon\b"#,
            #"\bdate\b"#,
            #"\btoday\b"#,
            #"\btonight\b"#,
            #"\byesterday\b"#,
            #"\blast\b"#,
            #"\bthis\b"#,
            #"\b(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#
        ]
        if containsAnyPattern(in: context, patterns: datePatterns) {
            return true
        }

        let stakePatterns = [
            #"\bstakes?\b"#,
            #"\bblinds?\b"#,
            #"\bplo\b"#,
            #"\bnlh\b"#,
            #"\bhold(?:'em|em|\s+em)\b"#,
            #"\bomaha\b"#,
            #"\bcash\b"#,
            #"\btournament\b"#,
            #"\bsng\b"#,
            #"\bplaying\b"#,
            #"\bplayed\b"#,
            #"\btable\b"#
        ]
        return !containsAnyPattern(in: context, patterns: stakePatterns)
    }

    private static func parseMonthNameDate(from text: String, relativeTo referenceDate: Date, using calendar: Calendar) -> Date? {
        let monthNames = #"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"#

        let patterns = [
            "\\b(\(monthNames))\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,\\s*(\\d{4}))?\\b",
            "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthNames))(?:\\s+(\\d{4}))?\\b"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                continue
            }

            let first = extractOptionalMatch(match, at: 1, in: text)
            let second = extractOptionalMatch(match, at: 2, in: text)
            let third = extractOptionalMatch(match, at: 3, in: text)

            let monthString: String
            let dayString: String
            if let first, monthNumber(from: first) != nil {
                monthString = first
                dayString = second ?? ""
            } else {
                monthString = second ?? ""
                dayString = first ?? ""
            }

            guard let month = monthNumber(from: monthString),
                  let day = Int(dayString) else {
                continue
            }

            let year = third.flatMap(Int.init) ?? calendar.component(.year, from: referenceDate)
            var components = calendar.dateComponents([.hour, .minute, .second], from: referenceDate)
            components.year = year
            components.month = month
            components.day = day

            guard let parsedDate = calendar.date(from: components) else { continue }
            if third != nil || parsedDate <= referenceDate {
                return parsedDate
            }
            return calendar.date(byAdding: .year, value: -1, to: parsedDate)
        }

        return nil
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

    private static func isLikelyVenue(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.contains(where: \.isLetter) else { return false }
        if parseStakes(from: normalized) != nil { return false }
        if parseClockTimeRange(from: normalized) != nil { return false }
        if parseNumericValue(from: normalized) != nil { return false }

        let invalidPatterns = [
            #"\bplo(?:5)?\b"#,
            #"\bnlh\b"#,
            #"\bhold(?:'em|em|\s+em)\b"#,
            #"\bstud\b"#,
            #"\brazz\b"#,
            #"\bbadugi\b"#,
            #"\bcash\s+game\b"#,
            #"\btournament\b"#,
            #"\bsng\b"#,
            #"\bsit\s*(?:and|n)?\s*go\b"#,
            #"\bonline\b"#,
            #"\bhome\s+game\b"#,
            #"\bhours?\b"#,
            #"\b(?:am|pm)\b"#,
            #"^(?:table|seat|game|session|room)$"#
        ]
        return !containsAnyPattern(in: normalized, patterns: invalidPatterns)
    }

    private static func isShortDeckMention(in text: String) -> Bool {
        if containsAnyPattern(in: text, patterns: [#"\bshort\s+deck\b"#, #"\bsix\s+plus\b"#]) {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "6+" {
            return true
        }

        return containsAnyPattern(
            in: text,
            patterns: [
                #"\b6\+\s*(?:hold(?:'em|em|\s+em)?|poker)\b"#,
                #"\bhold(?:'em|em|\s+em)?\s*6\+\b"#,
                #"\bpoker\s*6\+\b"#
            ]
        )
    }

    private static func appendFixedAmountMatches(
        using patterns: [String],
        in text: String,
        priority: Int,
        value: Double,
        into candidates: inout [AmountCandidate]
    ) {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                candidates.append(
                    AmountCandidate(
                        value: value,
                        priority: priority,
                        location: match.range.location
                    )
                )
            }
        }
    }

    private static func appendAmountMatches(
        using patterns: [String],
        in text: String,
        priority: Int,
        transform: (Double) -> Double,
        into candidates: inout [AmountCandidate],
        shouldFilterMidSession: Bool = true
    ) {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text),
                      let number = parseNumericValue(from: String(text[range])) else {
                    continue
                }
                if shouldFilterMidSession && isMidSessionReference(match: match, in: text) {
                    continue
                }
                candidates.append(
                    AmountCandidate(
                        value: transform(number),
                        priority: priority,
                        location: match.range.location
                    )
                )
            }
        }
    }

    private static func compareAmountCandidates(_ lhs: AmountCandidate, _ rhs: AmountCandidate) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        return lhs.location < rhs.location
    }

    private static func isMidSessionReference(match: NSTextCheckingResult, in text: String) -> Bool {
        let nsText = text as NSString
        let fullRange = match.range(at: 0)

        let prefixStart = max(0, fullRange.location - 24)
        let prefixRange = NSRange(location: prefixStart, length: fullRange.location - prefixStart)
        let prefix = nsText.substring(with: prefixRange).lowercased()

        let suffixEnd = min(nsText.length, fullRange.location + fullRange.length + 28)
        let suffixRange = NSRange(
            location: fullRange.location + fullRange.length,
            length: suffixEnd - (fullRange.location + fullRange.length)
        )
        let suffix = nsText.substring(with: suffixRange).lowercased()

        let prefixMarkers = [
            "was ",
            "were ",
            "being ",
            "originally ",
            "started ",
            "peak ",
            "peaked ",
            "earlier "
        ]

        let suffixMarkers = [
            "at one point",
            "earlier",
            "before punting",
            "before dusting",
            "before spewing",
            "before losing"
        ]

        return prefixMarkers.contains(where: prefix.contains) || suffixMarkers.contains(where: suffix.contains)
    }

    private static func extractNumbers(using pattern: String, in text: String) -> [(range: NSRange, value: Double)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = parseNumericValue(from: String(text[range])) else {
                return nil
            }
            return (match.range(at: 1), value)
        }
    }

    private static func extractFlexibleNumber(using pattern: String, primaryGroup: Int = 1, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: primaryGroup), in: text) else {
            return nil
        }
        return parseNumericValue(from: String(text[range]))
    }

    /// Extracts two numeric values from the first regex match (groups 1 and 2). Guarantees both come from the same match.
    private static func extractTwoNumbers(using pattern: String, in text: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range1 = Range(match.range(at: 1), in: text),
              let range2 = Range(match.range(at: 2), in: text),
              let a = parseNumericValue(from: String(text[range1])),
              let b = parseNumericValue(from: String(text[range2])) else {
            return nil
        }
        return (a, b)
    }

    private static func parseClockTimeRange(from text: String) -> Double? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|-|–)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let startHourRange = Range(match.range(at: 1), in: text),
                  let endHourRange = Range(match.range(at: 4), in: text),
                  let startHour = Int(text[startHourRange]),
                  let endHour = Int(text[endHourRange]) else {
                continue
            }

            let hasColon = match.range(at: 2).location != NSNotFound || match.range(at: 5).location != NSNotFound
            let startMinute = extractOptionalMatch(match, at: 2, in: text).flatMap(Int.init) ?? 0
            let endMinute = extractOptionalMatch(match, at: 5, in: text).flatMap(Int.init) ?? 0
            let startPeriod = extractOptionalMatch(match, at: 3, in: text)
            let endPeriod = extractOptionalMatch(match, at: 6, in: text)

            if !hasColon, startPeriod == nil, endPeriod == nil {
                let fullText = (text as NSString).substring(with: match.range(at: 0))
                guard isLikelyBareTimeRange(fullText, matchRange: match.range(at: 0), in: text) else {
                    continue
                }
            }

            if let duration = inferredMinuteSpan(
                startHour: startHour,
                startMinute: startMinute,
                startPeriod: startPeriod,
                endHour: endHour,
                endMinute: endMinute,
                endPeriod: endPeriod
            ) {
                return duration
            }
        }

        return nil
    }

    private static func parseBuyIn(from text: String) -> Double? {
        firstLabeledCurrency(
            patterns: [
                "(?:buy(?:\\s|-)?in|bought\\s*in)\\s*(?:for\\s*)?\(numberCapturePattern)",
                "\\bin\\s+for\\s+\(numberCapturePattern)\\b",
                "(?:^|[\\s,;])(?:played|entered|registered(?:\\s+for)?|fired)?\\s*(?:a|an)?\\s*\(numberCapturePattern)\\s+(?:tournament|mtt|sng|sit\\s*(?:and|n)?\\s*go)\\b"
            ],
            in: text
        )
    }

    private static func parseCashOut(from text: String) -> Double? {
        firstLabeledCurrency(
            patterns: [
                "(?:cash(?:ed)?\\s*out|cashed|cashout)\\s*(?:for\\s*)?\(numberCapturePattern)",
                "\\bout\\s+for\\s+\(numberCapturePattern)\\b",
                "(?:left|ended|finished)(?:\\s+the\\s+(?:session|night|day))?\\s+with\\s+\(numberCapturePattern)"
            ],
            in: text
        )
    }

    private static func parseTournamentPosition(from text: String) -> Int? {
        if let digits = extractMatch(
            using: #"(?:finished|came(?:\s+in)?|placed|busted(?:\s+in)?)\s+(\d+)(?:st|nd|rd|th)\b"#,
            in: text
        ) {
            return Int(digits)
        }

        if hasTournamentContext(in: text),
           let digits = extractMatch(
            using: #"(?:finished|came(?:\s+in)?|placed|busted(?:\s+in)?|ended)\s+(\d+)\b"#,
            in: text
           ) {
            return Int(digits)
        }

        return extractMatch(
            using: #"(?:finished|came(?:\s+in)?|placed|busted(?:\s+in)?)\s+(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth)\b"#,
            in: text
        ).flatMap(parseOrdinalValue(from:))
    }

    /// Parses total buy-ins (bullets). Returns 1–12. Nil if not found.
    private static func parseBuyins(from text: String) -> Int? {
        if let token = extractMatch(
            using: #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+bullets?\b"#,
            in: text
        ), let n = parseCountValue(from: token), n > 0, hasTournamentContext(in: text) {
            return min(12, max(1, n))
        }
        if let token = extractMatch(
            using: #"\b(?:fired|used|took)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+bullets?\b"#,
            in: text
        ), let n = parseCountValue(from: token), n > 0, hasTournamentContext(in: text) {
            return min(12, max(1, n))
        }
        if let token = extractMatch(
            using: #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+buy-?ins?\b"#,
            in: text
        ), let n = parseCountValue(from: token), n > 0, hasTournamentContext(in: text) {
            return min(12, max(1, n))
        }
        if let token = extractMatch(
            using: #"\b(\d+|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+re-?buys?\b"#,
            in: text
        ), let rebuys = parseCountValue(from: token), rebuys >= 0 {
            return min(12, max(1, rebuys + 1))
        }
        if let token = extractMatch(
            using: #"\brebought\s+(\d+|once|twice|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s+times?)?\b"#,
            in: text
        ), let rebuys = parseCountValue(from: token), rebuys >= 0 {
            return min(12, max(1, rebuys + 1))
        }
        if text.contains("one rebuy") || text.contains("1 rebuy") {
            return 2
        }
        return nil
    }

    private static func firstLabeledCurrency(patterns: [String], in text: String) -> Double? {
        for pattern in patterns {
            if let value = extractFlexibleNumber(using: pattern, in: text) {
                return abs(value)
            }
        }
        return nil
    }

    private static func containsAnyPattern(in text: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    private static func isLikelyStakesExpression(_ value: String, matchRange: NSRange, in text: String) -> Bool {
        if containsSupportedCurrencyToken(in: value) {
            return true
        }

        if value.contains("/"), isLikelySlashDateExpression(value, matchRange: matchRange, in: text) {
            return false
        }

        let context = surroundingContext(for: matchRange, in: text, window: 20)
        let strongStakePatterns = [
            #"\bstakes?\b"#,
            #"\bblinds?\b"#,
            #"\bplo\b"#,
            #"\bnlh\b"#,
            #"\bhold(?:'em|em|\s+em)\b"#,
            #"\bomaha\b"#,
            #"\bstud\b"#,
            #"\brazz\b"#,
            #"\bbadugi\b"#,
            #"\bcash\b"#,
            #"\blive\b"#,
            #"\bonline\b"#,
            #"\btournament\b"#,
            #"\bsng\b"#,
            #"\bpoker\b"#
        ]
        let weakStakePatterns = [
            #"\bplaying\b"#,
            #"\bplayed\b"#,
            #"\btable\b"#
        ]
        let timePatterns = [
            #"\bfrom\b"#,
            #"\bbetween\b"#,
            #"\bstarted\b"#,
            #"\bended\b"#,
            #"\buntil\b"#,
            #"\btill\b"#,
            #"\blasted\b"#,
            #"\bsession\b"#,
            #"\bhours?\b"#,
            #"\bminutes?\b"#,
            #"\bmins?\b"#,
            #"\btime\b"#,
            #"\b(?:am|pm)\b"#
        ]

        if containsAnyPattern(in: context, patterns: timePatterns) {
            return false
        }

        if value.contains("/") {
            return isCommonBlindStructure(value)
        }

        if containsAnyPattern(in: context, patterns: strongStakePatterns) {
            return true
        }

        if containsAnyPattern(in: context, patterns: weakStakePatterns) {
            return isCommonBlindStructure(value)
        }

        return false
    }

    private static func isLikelySlashDateExpression(_ value: String, matchRange: NSRange, in text: String) -> Bool {
        guard !containsSupportedCurrencyToken(in: value),
              let (first, second) = numericPair(from: value),
              floor(first) == first,
              floor(second) == second,
              (1...12).contains(Int(first)),
              (1...31).contains(Int(second)) else {
            return false
        }

        let context = surroundingContext(for: matchRange, in: text, window: 24)
        let datePatterns = [
            #"\bon\b"#,
            #"\bdate\b"#,
            #"\btoday\b"#,
            #"\btonight\b"#,
            #"\byesterday\b"#,
            #"\blast\b"#,
            #"\bthis\b"#,
            #"\b(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#
        ]
        return containsAnyPattern(in: context, patterns: datePatterns)
    }

    private static func isLikelyBareTimeRange(_ value: String, matchRange: NSRange, in text: String) -> Bool {
        if value.contains("/") || containsSupportedCurrencyToken(in: value) {
            return false
        }

        let context = surroundingContext(for: matchRange, in: text, window: 20)
        let stakePatterns = [
            #"\bstakes?\b"#,
            #"\bblinds?\b"#,
            #"\bplo\b"#,
            #"\bnlh\b"#,
            #"\bhold(?:'em|em|\s+em)\b"#,
            #"\bomaha\b"#,
            #"\bcash\b"#,
            #"\btournament\b"#,
            #"\bsng\b"#,
            #"\bplaying\b"#,
            #"\bplayed\b"#
        ]
        if containsAnyPattern(in: context, patterns: stakePatterns) {
            return false
        }

        let timePatterns = [
            #"\bfrom\b"#,
            #"\bbetween\b"#,
            #"\bstarted\b"#,
            #"\bended\b"#,
            #"\buntil\b"#,
            #"\btill\b"#,
            #"\blasted\b"#,
            #"\bsession\b"#,
            #"\bhours?\b"#,
            #"\btime\b"#
        ]
        return containsAnyPattern(in: context, patterns: timePatterns)
    }

    private static func surroundingContext(for matchRange: NSRange, in text: String, window: Int) -> String {
        let nsText = text as NSString
        let prefixStart = max(0, matchRange.location - window)
        let prefix = nsText.substring(with: NSRange(location: prefixStart, length: matchRange.location - prefixStart)).lowercased()
        let suffixEnd = min(nsText.length, matchRange.location + matchRange.length + window)
        let suffix = nsText.substring(
            with: NSRange(location: matchRange.location + matchRange.length, length: suffixEnd - (matchRange.location + matchRange.length))
        ).lowercased()
        return "\(prefix) \(suffix)"
    }

    private static func isCommonBlindStructure(_ value: String) -> Bool {
        guard let (smallBlind, bigBlind) = numericPair(from: value),
              smallBlind > 0,
              bigBlind >= smallBlind else {
            return false
        }

        let hasDecimal = floor(smallBlind) != smallBlind || floor(bigBlind) != bigBlind || smallBlind < 1 || bigBlind < 1
        if hasDecimal || smallBlind <= 5 {
            return true
        }

        let roundedSmallBlind = Int(smallBlind)
        let roundedBigBlind = Int(bigBlind)
        if roundedSmallBlind > 0,
           roundedBigBlind > 0,
           roundedSmallBlind.isMultiple(of: 5),
           roundedBigBlind.isMultiple(of: 5) {
            return true
        }

        let ratio = bigBlind / smallBlind
        let commonRatios = [1.0, 2.0, 2.5, 3.0, 5.0]
        return commonRatios.contains(where: { abs($0 - ratio) < 0.001 })
    }

    private static func numericPair(from value: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: stakesPairPattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let left = extractOptionalMatch(match, at: 1, in: value).flatMap(parseNumericValue(from:)),
              let right = extractOptionalMatch(match, at: 2, in: value).flatMap(parseNumericValue(from:)) else {
            return nil
        }
        return (left, right)
    }

    private static func trimTrailingVenueNoise(_ value: String) -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingNoisePatterns = [
            #"\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:to|-|–)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*$"#,
            #"\s+(?:"# + stakesTriplePattern + "|" + stakesPairPattern + #")\s*$"#,
            #"\s+(?:plo(?:5)?|nlh|hold(?:'em|em|\s+em)|omaha(?:\s+hi[\s-]*lo)?|o8|razz|badugi|stud|tournament|sng)\s*$"#,
            #"\s+(?:today|tonight|yesterday|last\s+night|this\s+(?:morning|afternoon|evening))\s*$"#,
            #"\s+(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?:\s+(?:night|morning|afternoon|evening))?\s*$"#,
            #"\s+on\s+(?:today|tonight|yesterday|last\s+night|this\s+(?:morning|afternoon|evening))\s*$"#,
            #"\s+on\s+(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?:\s+(?:night|morning|afternoon|evening))?\s*$"#,
            #"\s+on\s+\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\s*$"#,
            #"\s+on\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?(?:,\s*\d{4})?\s*$"#
        ]

        var removedNoise = true
        while removedNoise {
            removedNoise = false
            for pattern in trailingNoisePatterns {
                guard let range = firstMatchRange(using: pattern, in: candidate),
                      range.lowerBound != candidate.startIndex else {
                    continue
                }
                candidate = String(candidate[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                removedNoise = true
                break
            }
        }

        return candidate
    }

    private static func hasTournamentContext(in text: String) -> Bool {
        containsAnyPattern(
            in: text,
            patterns: [
                #"\btournament\b"#,
                #"\bmtt\b"#,
                #"\bsng\b"#,
                #"\bsit\s*(?:and|n)?\s*go\b"#,
                #"\bre-?buy\b"#,
                #"\badd-?on\b"#,
                #"\bfinal\s+table\b"#,
                #"\bcashed\b"#,
                #"\bitm\b"#,
                #"\bfield\b"#,
                #"\bentr(?:y|ies|ants)\b"#,
                #"\bbounty\b"#
            ]
        )
    }

    private static func containsSupportedCurrencyToken(in value: String) -> Bool {
        let normalized = value.lowercased()
        return supportedCurrencyTokens.contains(where: normalized.contains)
    }

    private static func resolvedStakeCurrencyCode(from value: String) -> String? {
        let normalized = value.lowercased()
        for currency in SupportedCurrency.all {
            if normalized.contains(currency.symbol.lowercased()) || normalized.contains(currency.code.lowercased()) {
                return currency.code
            }
        }
        return nil
    }

    private static func formatStakesOutput(small: String, big: String, straddle: String, currencyCode: String) -> String {
        let sym = SupportedCurrency.symbol(for: currencyCode)
        let before = SupportedCurrency.symbolBeforeAmount(for: currencyCode)
        func part(_ n: String) -> String { before ? "\(sym)\(n)" : "\(n) \(sym)" }
        if straddle.isEmpty {
            return "\(part(small))/\(part(big))"
        }
        return "\(part(small))/\(part(big))/\(part(straddle))"
    }

    private static func parseCountValue(from text: String) -> Int? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "once":
            return 1
        case "twice":
            return 2
        default:
            return parseOrdinalValue(from: normalized)
        }
    }

    private static func parseBareMinutesDuration(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*m\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let minutes = parseNumericValue(from: String(text[range])) else {
            return nil
        }

        let fullRange = match.range(at: 0)
        let nsText = text as NSString
        let fullMatch = nsText.substring(with: fullRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == fullMatch {
            return minutes / 60
        }

        let context = surroundingContext(for: fullRange, in: text, window: 24)
        guard minutes >= 5, minutes <= (24 * 60) else {
            return nil
        }

        let timePatterns = [
            #"\bplay(?:ed|ing)?\b"#,
            #"\bsession\b"#,
            #"\blasted\b"#,
            #"\bduration\b"#,
            #"\btime\b"#
        ]
        guard containsAnyPattern(in: context, patterns: timePatterns) else {
            return nil
        }
        return minutes / 60
    }

    private static func firstMatchRange(using pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return Range(match.range(at: 0), in: text)
    }

    private static func monthNumber(from value: String) -> Int? {
        let normalized = value.lowercased()
        switch normalized {
        case "jan", "january": return 1
        case "feb", "february": return 2
        case "mar", "march": return 3
        case "apr", "april": return 4
        case "may": return 5
        case "jun", "june": return 6
        case "jul", "july": return 7
        case "aug", "august": return 8
        case "sep", "sept", "september": return 9
        case "oct", "october": return 10
        case "nov", "november": return 11
        case "dec", "december": return 12
        default: return nil
        }
    }

    private static let rakePatterns = [
        "(?:rake|time charge|time collection|time fee|drop)\\s*(?:was|were|for|cost)?\\s*\(numberCapturePattern)",
        "paid\\s+\(numberCapturePattern)\\s+in\\s+(?:rake|time)"
    ]

    private static let tipsPatterns = [
        "(?:tip(?:ped)?|tips?)\\s+(?:the\\s+dealer\\s+)?\(numberCapturePattern)",
        "\(numberCapturePattern)\\s+tip\\b",
        "tips?\\s*(?:were|was|for|cost)?\\s*\(numberCapturePattern)"
    ]

    private static let foodPatterns = [
        "spent\\s+\(numberCapturePattern)\\s+on\\s+(?:food|meal|dinner|lunch|breakfast)",
        "(?:food|meal|dinner|lunch|breakfast)\\s*(?:was|cost|for)?\\s*\(numberCapturePattern)"
    ]

    private static let travelPatterns = [
        "spent\\s+\(numberCapturePattern)\\s+on\\s+(?:travel|uber|lyft|gas|parking|tolls?)",
        "(?:travel|uber|lyft|gas|parking|tolls?)\\s*(?:was|cost|for)?\\s*\(numberCapturePattern)"
    ]

    private static let feesPatterns = [
        "(?:fees?|entry fees?|seat fees?|membership fees?)\\s*(?:were|was|cost|for)?\\s*\(numberCapturePattern)"
    ]
}
