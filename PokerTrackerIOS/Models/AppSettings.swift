//
//  AppSettings.swift
//  PokerTrackerIOS
//

import Foundation
import SwiftUI

struct SupportedCurrency: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String

    var id: String { code }
    var pickerLabel: String { "\(code) - \(name)" }

    static let all: [SupportedCurrency] = [
        SupportedCurrency(code: "USD", name: "US Dollar", symbol: "$"),
        SupportedCurrency(code: "EUR", name: "Euro", symbol: "€"),
        SupportedCurrency(code: "GBP", name: "British Pound", symbol: "£"),
        SupportedCurrency(code: "CHF", name: "Swiss Franc", symbol: "CHF"),
        SupportedCurrency(code: "SEK", name: "Swedish Krona", symbol: "kr"),
        SupportedCurrency(code: "NOK", name: "Norwegian Krone", symbol: "kr"),
        SupportedCurrency(code: "DKK", name: "Danish Krone", symbol: "kr"),
        SupportedCurrency(code: "PLN", name: "Polish Zloty", symbol: "zł"),
        SupportedCurrency(code: "CZK", name: "Czech Koruna", symbol: "Kč"),
        SupportedCurrency(code: "HUF", name: "Hungarian Forint", symbol: "Ft"),
        SupportedCurrency(code: "RON", name: "Romanian Leu", symbol: "lei"),
        SupportedCurrency(code: "TRY", name: "Turkish Lira", symbol: "₺"),
        SupportedCurrency(code: "JPY", name: "Japanese Yen", symbol: "¥"),
        SupportedCurrency(code: "CNY", name: "Chinese Yuan", symbol: "¥"),
        SupportedCurrency(code: "HKD", name: "Hong Kong Dollar", symbol: "HK$"),
        SupportedCurrency(code: "SGD", name: "Singapore Dollar", symbol: "S$"),
        SupportedCurrency(code: "KRW", name: "South Korean Won", symbol: "₩"),
        SupportedCurrency(code: "TWD", name: "New Taiwan Dollar", symbol: "NT$"),
        SupportedCurrency(code: "THB", name: "Thai Baht", symbol: "฿"),
        SupportedCurrency(code: "INR", name: "Indian Rupee", symbol: "₹"),
        SupportedCurrency(code: "PHP", name: "Philippine Peso", symbol: "₱"),
        SupportedCurrency(code: "MYR", name: "Malaysian Ringgit", symbol: "RM"),
        SupportedCurrency(code: "VND", name: "Vietnamese Dong", symbol: "₫")
    ]

    static func symbol(for code: String) -> String {
        all.first(where: { $0.code == code })?.symbol ?? currencyFormatter(for: code).currencySymbol ?? "$"
    }

    /// Locale for this currency so formatting matches how it reads in that country (e.g. USD and CAD both use $ before amount)
    static func localeIdentifier(for code: String) -> String {
        switch code {
        case "USD": return "en_US"
        case "EUR": return "de_DE"
        case "GBP": return "en_GB"
        case "CHF": return "de_CH"
        case "SEK": return "sv_SE"
        case "NOK": return "nb_NO"
        case "DKK": return "da_DK"
        case "PLN": return "pl_PL"
        case "CZK": return "cs_CZ"
        case "HUF": return "hu_HU"
        case "RON": return "ro_RO"
        case "TRY": return "tr_TR"
        case "JPY": return "ja_JP"
        case "CNY": return "zh_CN"
        case "HKD": return "zh_HK"
        case "SGD": return "en_SG"
        case "KRW": return "ko_KR"
        case "TWD": return "zh_TW"
        case "THB": return "th_TH"
        case "INR": return "en_IN"
        case "PHP": return "en_PH"
        case "MYR": return "ms_MY"
        case "VND": return "vi_VN"
        default: return "en_US"
        }
    }

    private static func currencyFormatter(for code: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.locale = Locale(identifier: localeIdentifier(for: code))
        return f
    }

    /// Derived from locale: true if symbol goes before amount (e.g. $100), false if after (e.g. 100 kr)
    static func symbolBeforeAmount(for code: String) -> Bool {
        let formatter = currencyFormatter(for: code)
        formatter.maximumFractionDigits = 0
        guard let str = formatter.string(from: 100) else { return true }
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        return trimmed.first?.isNumber != true
    }
}

/// Win/loss color scheme for accessibility (e.g. colorblind-friendly options)
enum ProfitLossColorScheme: String, Codable, CaseIterable {
    case `default` = "Default"
    case blueOrange = "Blue / Orange"
    case tealCoral = "Teal / Coral"
    case purpleAmber = "Purple / Amber"
    
    var winColor: Color {
        switch self {
        case .default: return .green
        case .blueOrange: return Color(red: 0.2, green: 0.5, blue: 0.9)
        case .tealCoral: return Color(red: 0.2, green: 0.7, blue: 0.7)
        case .purpleAmber: return Color(red: 0.5, green: 0.4, blue: 0.9)
        }
    }
    
    var lossColor: Color {
        switch self {
        case .default: return .red
        case .blueOrange: return Color(red: 0.95, green: 0.6, blue: 0.2)
        case .tealCoral: return Color(red: 0.95, green: 0.45, blue: 0.4)
        case .purpleAmber: return Color(red: 0.95, green: 0.7, blue: 0.2)
        }
    }
}

struct AppSettings: Codable {
    var currency: String
    var startingBankroll: Double
    var defaultGameType: GameType
    var defaultVariant: String?
    var defaultStakes: String?
    /// Ordered list of quick stake options. Each item is either a StakesPreset.rawValue (e.g. ".1/.2") or a custom stakes string (e.g. "$1/$2").
    var quickStakesList: [String]
    var pinnedVenueOptions: [String]
    var hiddenVenueOptions: [String]
    var showHourlyRate: Bool
    var deductExpensesFromProfit: Bool
    var hapticFeedback: Bool
    var use24HourTime: Bool
    var useCompactCurrency: Bool
    var showSessionNumbers: Bool
    var confirmBeforeDelete: Bool
    var hasSeenOnboarding: Bool
    var geminiAPIKey: String?
    var openAIAPIKey: String?
    var profitLossColorScheme: ProfitLossColorScheme
    var workerBaseURL: String
    var reminderEnabled: Bool

    static let defaultWorkerBaseURL = "https://poker-tracker-ai-proxy.pokerbankrollai.workers.dev"

    enum CodingKeys: String, CodingKey {
        case currency, startingBankroll, defaultGameType
        case defaultVariant, defaultStakes, quickStakesList
        case enabledStakesPresets, customStakesPresets // legacy, for migration
        case pinnedVenueOptions, hiddenVenueOptions, showHourlyRate, deductExpensesFromProfit, hapticFeedback
        case use24HourTime, useCompactCurrency, showSessionNumbers, confirmBeforeDelete
        case hasSeenOnboarding, geminiAPIKey, openAIAPIKey, profitLossColorScheme
        case workerBaseURL, reminderEnabled
    }

    static var defaultQuickStakesList: [String] {
        StakesPreset.defaultEnabledRawValues
    }

    init(
        currency: String,
        startingBankroll: Double,
        defaultGameType: GameType,
        defaultVariant: String?,
        defaultStakes: String?,
        quickStakesList: [String],
        pinnedVenueOptions: [String],
        hiddenVenueOptions: [String],
        showHourlyRate: Bool,
        deductExpensesFromProfit: Bool,
        hapticFeedback: Bool,
        use24HourTime: Bool,
        useCompactCurrency: Bool,
        showSessionNumbers: Bool,
        confirmBeforeDelete: Bool,
        hasSeenOnboarding: Bool,
        geminiAPIKey: String?,
        openAIAPIKey: String?,
        profitLossColorScheme: ProfitLossColorScheme,
        workerBaseURL: String = AppSettings.defaultWorkerBaseURL,
        reminderEnabled: Bool = true
    ) {
        self.currency = currency
        self.startingBankroll = startingBankroll
        self.defaultGameType = defaultGameType
        self.defaultVariant = defaultVariant
        self.defaultStakes = defaultStakes
        self.quickStakesList = Self.normalizedQuickStakesList(quickStakesList)
        self.pinnedVenueOptions = Self.normalizedVenueOptions(pinnedVenueOptions)
        self.hiddenVenueOptions = Self.normalizedVenueOptions(hiddenVenueOptions)
        self.showHourlyRate = showHourlyRate
        self.deductExpensesFromProfit = deductExpensesFromProfit
        self.hapticFeedback = hapticFeedback
        self.use24HourTime = use24HourTime
        self.useCompactCurrency = useCompactCurrency
        self.showSessionNumbers = showSessionNumbers
        self.confirmBeforeDelete = confirmBeforeDelete
        self.hasSeenOnboarding = hasSeenOnboarding
        self.geminiAPIKey = geminiAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.profitLossColorScheme = profitLossColorScheme
        self.workerBaseURL = workerBaseURL
        self.reminderEnabled = reminderEnabled
    }

    static let `default` = AppSettings(
        currency: "USD",
        startingBankroll: 0,
        defaultGameType: .cash,
        defaultVariant: PokerVariant.noLimitHoldem.rawValue,
        defaultStakes: nil,
        quickStakesList: defaultQuickStakesList,
        pinnedVenueOptions: [],
        hiddenVenueOptions: [],
        showHourlyRate: true,
        deductExpensesFromProfit: true,
        hapticFeedback: true,
        use24HourTime: false,
        useCompactCurrency: false,
        showSessionNumbers: true,
        confirmBeforeDelete: true,
        hasSeenOnboarding: false,
        geminiAPIKey: nil,
        openAIAPIKey: nil,
        profitLossColorScheme: .default
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? AppSettings.default.currency
        startingBankroll = try c.decodeIfPresent(Double.self, forKey: .startingBankroll) ?? AppSettings.default.startingBankroll
        defaultGameType = try c.decodeIfPresent(GameType.self, forKey: .defaultGameType) ?? AppSettings.default.defaultGameType
        defaultVariant = try c.decodeIfPresent(String.self, forKey: .defaultVariant) ?? PokerVariant.noLimitHoldem.rawValue
        defaultStakes = try c.decodeIfPresent(String.self, forKey: .defaultStakes)
        if let list = try c.decodeIfPresent([String].self, forKey: .quickStakesList) {
            quickStakesList = Self.normalizedQuickStakesList(list)
        } else {
            let enabled = try c.decodeIfPresent([String].self, forKey: .enabledStakesPresets) ?? AppSettings.defaultQuickStakesList
            let custom = try c.decodeIfPresent([String].self, forKey: .customStakesPresets) ?? []
            quickStakesList = Self.normalizedQuickStakesList(
                StakesPreset.enabledPresets(from: enabled).map(\.rawValue) + AppSettings.normalizedCustomStakesPresets(custom)
            )
        }
        pinnedVenueOptions = Self.normalizedVenueOptions(
            try c.decodeIfPresent([String].self, forKey: .pinnedVenueOptions) ?? AppSettings.default.pinnedVenueOptions
        )
        hiddenVenueOptions = Self.normalizedVenueOptions(
            try c.decodeIfPresent([String].self, forKey: .hiddenVenueOptions) ?? AppSettings.default.hiddenVenueOptions
        )
        showHourlyRate = try c.decodeIfPresent(Bool.self, forKey: .showHourlyRate) ?? AppSettings.default.showHourlyRate
        deductExpensesFromProfit = try c.decodeIfPresent(Bool.self, forKey: .deductExpensesFromProfit) ?? AppSettings.default.deductExpensesFromProfit
        hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? AppSettings.default.hapticFeedback
        use24HourTime = try c.decodeIfPresent(Bool.self, forKey: .use24HourTime) ?? AppSettings.default.use24HourTime
        useCompactCurrency = try c.decodeIfPresent(Bool.self, forKey: .useCompactCurrency) ?? AppSettings.default.useCompactCurrency
        showSessionNumbers = try c.decodeIfPresent(Bool.self, forKey: .showSessionNumbers) ?? AppSettings.default.showSessionNumbers
        confirmBeforeDelete = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeDelete) ?? AppSettings.default.confirmBeforeDelete
        hasSeenOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? AppSettings.default.hasSeenOnboarding
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey)
        openAIAPIKey = try c.decodeIfPresent(String.self, forKey: .openAIAPIKey)
        profitLossColorScheme = try c.decodeIfPresent(ProfitLossColorScheme.self, forKey: .profitLossColorScheme) ?? AppSettings.default.profitLossColorScheme
        workerBaseURL = try c.decodeIfPresent(String.self, forKey: .workerBaseURL) ?? AppSettings.defaultWorkerBaseURL
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? AppSettings.default.reminderEnabled
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(startingBankroll, forKey: .startingBankroll)
        try c.encode(defaultGameType, forKey: .defaultGameType)
        try c.encodeIfPresent(defaultVariant, forKey: .defaultVariant)
        try c.encodeIfPresent(defaultStakes, forKey: .defaultStakes)
        try c.encode(Self.normalizedQuickStakesList(quickStakesList), forKey: .quickStakesList)
        try c.encode(Self.normalizedVenueOptions(pinnedVenueOptions), forKey: .pinnedVenueOptions)
        try c.encode(Self.normalizedVenueOptions(hiddenVenueOptions), forKey: .hiddenVenueOptions)
        try c.encode(showHourlyRate, forKey: .showHourlyRate)
        try c.encode(deductExpensesFromProfit, forKey: .deductExpensesFromProfit)
        try c.encode(hapticFeedback, forKey: .hapticFeedback)
        try c.encode(use24HourTime, forKey: .use24HourTime)
        try c.encode(useCompactCurrency, forKey: .useCompactCurrency)
        try c.encode(showSessionNumbers, forKey: .showSessionNumbers)
        try c.encode(confirmBeforeDelete, forKey: .confirmBeforeDelete)
        try c.encode(hasSeenOnboarding, forKey: .hasSeenOnboarding)
        try c.encodeIfPresent(geminiAPIKey, forKey: .geminiAPIKey)
        try c.encodeIfPresent(openAIAPIKey, forKey: .openAIAPIKey)
        try c.encode(profitLossColorScheme, forKey: .profitLossColorScheme)
        try c.encode(workerBaseURL, forKey: .workerBaseURL)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
    }

    func displayAmount(_ value: Double, compact: Bool? = nil, includePositiveSign: Bool = true) -> String {
        let useCompact = compact ?? useCompactCurrency
        guard useCompact else {
            return PokerSession.formatCurrency(value, currency: currency)
        }

        let prefix: String
        if value < 0 {
            prefix = "-"
        } else if value > 0, includePositiveSign {
            prefix = "+"
        } else {
            prefix = ""
        }

        return prefix + PokerSession.formatCompactCurrency(abs(value), currency: currency)
    }

    func displayUnsignedAmount(_ value: Double, compact: Bool? = nil) -> String {
        let useCompact = compact ?? useCompactCurrency
        if useCompact {
            return PokerSession.formatCompactCurrency(abs(value), currency: currency)
        }
        return PokerSession.formatCurrency(abs(value), currency: currency)
    }

    func displayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if use24HourTime {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    func displayTimeRange(from start: Date, to end: Date) -> String {
        "\(displayTime(start)) – \(displayTime(end))"
    }

    /// Normalizes, deduplicates, and sorts quick stakes list by numerical value (small blind, then big blind).
    static func normalizedQuickStakesList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized: String
            if StakesPreset(rawValue: value) != nil {
                normalized = value
            } else if let custom = normalizedCustomStakesValue(value) {
                normalized = custom
            } else {
                continue
            }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result.sorted { lhs, rhs in
            let l = stakeSortKey(lhs)
            let r = stakeSortKey(rhs)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return l.2 < r.2
        }
    }

    /// Parses stake string into (smallBlind, bigBlind, thirdBlind) for sorting. Unparseable use greatestFiniteMagnitude.
    private static func stakeSortKey(_ stake: String) -> (Double, Double, Double) {
        let parts = stake.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2,
              let small = SessionParserService.parseNumericValue(from: parts[0]),
              let big = SessionParserService.parseNumericValue(from: parts[1]) else {
            return (Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        }
        let third: Double? = parts.count >= 3 ? SessionParserService.parseNumericValue(from: parts[2]) : 0.0
        return (small, big, third ?? 0)
    }

    static func normalizedCustomStakesValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard (parts.count == 2 || parts.count == 3),
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              parts.count == 2 || !parts[2].isEmpty else {
            return nil
        }

        return parts.joined(separator: "/")
    }

    /// Normalizes and deduplicates custom stake presets (e.g. "$1/$2", "£3/£5").
    static func normalizedCustomStakesPresets(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let normalized = normalizedCustomStakesValue(value) else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    static func normalizedVenueOptions(_ venues: [String]) -> [String] {
        VenueCleaner.normalizedList(venues)
    }
}
