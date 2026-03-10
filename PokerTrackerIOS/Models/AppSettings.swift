//
//  AppSettings.swift
//  PokerTrackerIOS
//

import Foundation
import SwiftUI

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
        case defaultVariant, defaultStakes, showHourlyRate, hapticFeedback
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
        currency = try c.decode(String.self, forKey: .currency)
        startingBankroll = try c.decode(Double.self, forKey: .startingBankroll)
        defaultGameType = try c.decode(GameType.self, forKey: .defaultGameType)
        defaultVariant = try c.decodeIfPresent(String.self, forKey: .defaultVariant)
        defaultStakes = try c.decodeIfPresent(String.self, forKey: .defaultStakes)
        showHourlyRate = try c.decode(Bool.self, forKey: .showHourlyRate)
        hapticFeedback = try c.decode(Bool.self, forKey: .hapticFeedback)
        use24HourTime = try c.decodeIfPresent(Bool.self, forKey: .use24HourTime) ?? false
        useCompactCurrency = try c.decodeIfPresent(Bool.self, forKey: .useCompactCurrency) ?? false
        showSessionNumbers = try c.decodeIfPresent(Bool.self, forKey: .showSessionNumbers) ?? true
        confirmBeforeDelete = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeDelete) ?? true
        hasSeenOnboarding = try c.decode(Bool.self, forKey: .hasSeenOnboarding)
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey)
        openAIAPIKey = try c.decodeIfPresent(String.self, forKey: .openAIAPIKey)
        profitLossColorScheme = try c.decodeIfPresent(ProfitLossColorScheme.self, forKey: .profitLossColorScheme) ?? .default
        workerBaseURL = try c.decodeIfPresent(String.self, forKey: .workerBaseURL) ?? AppSettings.defaultWorkerBaseURL
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(startingBankroll, forKey: .startingBankroll)
        try c.encode(defaultGameType, forKey: .defaultGameType)
        try c.encodeIfPresent(defaultVariant, forKey: .defaultVariant)
        try c.encodeIfPresent(defaultStakes, forKey: .defaultStakes)
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
}
