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
        SupportedCurrency(code: "PLN", name: "Polish Zloty", symbol: "zl"),
        SupportedCurrency(code: "CZK", name: "Czech Koruna", symbol: "Kc"),
        SupportedCurrency(code: "HUF", name: "Hungarian Forint", symbol: "Ft"),
        SupportedCurrency(code: "RON", name: "Romanian Leu", symbol: "lei"),
        SupportedCurrency(code: "TRY", name: "Turkish Lira", symbol: "TL"),
        SupportedCurrency(code: "JPY", name: "Japanese Yen", symbol: "JP¥"),
        SupportedCurrency(code: "CNY", name: "Chinese Yuan", symbol: "CN¥"),
        SupportedCurrency(code: "HKD", name: "Hong Kong Dollar", symbol: "HK$"),
        SupportedCurrency(code: "SGD", name: "Singapore Dollar", symbol: "SG$"),
        SupportedCurrency(code: "KRW", name: "South Korean Won", symbol: "₩"),
        SupportedCurrency(code: "TWD", name: "New Taiwan Dollar", symbol: "NT$"),
        SupportedCurrency(code: "THB", name: "Thai Baht", symbol: "฿"),
        SupportedCurrency(code: "INR", name: "Indian Rupee", symbol: "₹"),
        SupportedCurrency(code: "PHP", name: "Philippine Peso", symbol: "₱"),
        SupportedCurrency(code: "MYR", name: "Malaysian Ringgit", symbol: "RM"),
        SupportedCurrency(code: "VND", name: "Vietnamese Dong", symbol: "₫")
    ]

    static func symbol(for code: String) -> String {
        all.first(where: { $0.code == code })?.symbol ?? "$"
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
    var enabledStakesPresets: [String]
    var pinnedVenueOptions: [String]
    var hiddenVenueOptions: [String]
    var showHourlyRate: Bool
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
        case defaultVariant, defaultStakes, enabledStakesPresets, pinnedVenueOptions, hiddenVenueOptions, showHourlyRate, hapticFeedback
        case use24HourTime, useCompactCurrency, showSessionNumbers, confirmBeforeDelete
        case hasSeenOnboarding, geminiAPIKey, openAIAPIKey, profitLossColorScheme
        case workerBaseURL, reminderEnabled
    }

    init(
        currency: String,
        startingBankroll: Double,
        defaultGameType: GameType,
        defaultVariant: String?,
        defaultStakes: String?,
        enabledStakesPresets: [String],
        pinnedVenueOptions: [String],
        hiddenVenueOptions: [String],
        showHourlyRate: Bool,
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
        self.enabledStakesPresets = Self.normalizedEnabledStakesPresets(enabledStakesPresets)
        self.pinnedVenueOptions = Self.normalizedVenueOptions(pinnedVenueOptions)
        self.hiddenVenueOptions = Self.normalizedVenueOptions(hiddenVenueOptions)
        self.showHourlyRate = showHourlyRate
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
        enabledStakesPresets: StakesPreset.defaultEnabledRawValues,
        pinnedVenueOptions: [],
        hiddenVenueOptions: [],
        showHourlyRate: true,
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
        defaultVariant = try c.decodeIfPresent(String.self, forKey: .defaultVariant)
        defaultStakes = try c.decodeIfPresent(String.self, forKey: .defaultStakes)
        enabledStakesPresets = Self.normalizedEnabledStakesPresets(
            try c.decodeIfPresent([String].self, forKey: .enabledStakesPresets) ?? AppSettings.default.enabledStakesPresets
        )
        pinnedVenueOptions = Self.normalizedVenueOptions(
            try c.decodeIfPresent([String].self, forKey: .pinnedVenueOptions) ?? AppSettings.default.pinnedVenueOptions
        )
        hiddenVenueOptions = Self.normalizedVenueOptions(
            try c.decodeIfPresent([String].self, forKey: .hiddenVenueOptions) ?? AppSettings.default.hiddenVenueOptions
        )
        showHourlyRate = try c.decodeIfPresent(Bool.self, forKey: .showHourlyRate) ?? AppSettings.default.showHourlyRate
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
        try c.encode(Self.normalizedEnabledStakesPresets(enabledStakesPresets), forKey: .enabledStakesPresets)
        try c.encode(Self.normalizedVenueOptions(pinnedVenueOptions), forKey: .pinnedVenueOptions)
        try c.encode(Self.normalizedVenueOptions(hiddenVenueOptions), forKey: .hiddenVenueOptions)
        try c.encode(showHourlyRate, forKey: .showHourlyRate)
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

    static func normalizedEnabledStakesPresets(_ rawValues: [String]) -> [String] {
        StakesPreset.normalizedRawValues(rawValues)
    }

    static func normalizedVenueOptions(_ venues: [String]) -> [String] {
        VenueCleaner.normalizedList(venues)
    }
}
