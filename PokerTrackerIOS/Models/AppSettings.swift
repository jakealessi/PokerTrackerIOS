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
    var lowBankrollAlert: Double?
    var defaultGameType: GameType
    var defaultVariant: String?
    var defaultStakes: String?
    var showHourlyRate: Bool
    var hapticFeedback: Bool
    var hasSeenOnboarding: Bool
    var geminiAPIKey: String?
    var openAIAPIKey: String?
    var profitLossColorScheme: ProfitLossColorScheme

    enum CodingKeys: String, CodingKey {
        case currency, startingBankroll, lowBankrollAlert, defaultGameType
        case defaultVariant, defaultStakes, showHourlyRate, hapticFeedback
        case hasSeenOnboarding, geminiAPIKey, openAIAPIKey, profitLossColorScheme
    }

    init(
        currency: String,
        startingBankroll: Double,
        lowBankrollAlert: Double?,
        defaultGameType: GameType,
        defaultVariant: String?,
        defaultStakes: String?,
        showHourlyRate: Bool,
        hapticFeedback: Bool,
        hasSeenOnboarding: Bool,
        geminiAPIKey: String?,
        openAIAPIKey: String?,
        profitLossColorScheme: ProfitLossColorScheme
    ) {
        self.currency = currency
        self.startingBankroll = startingBankroll
        self.lowBankrollAlert = lowBankrollAlert
        self.defaultGameType = defaultGameType
        self.defaultVariant = defaultVariant
        self.defaultStakes = defaultStakes
        self.showHourlyRate = showHourlyRate
        self.hapticFeedback = hapticFeedback
        self.hasSeenOnboarding = hasSeenOnboarding
        self.geminiAPIKey = geminiAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.profitLossColorScheme = profitLossColorScheme
    }

    static let `default` = AppSettings(
        currency: "USD",
        startingBankroll: 0,
        lowBankrollAlert: nil,
        defaultGameType: .cash,
        defaultVariant: PokerVariant.noLimitHoldem.rawValue,
        defaultStakes: nil,
        showHourlyRate: true,
        hapticFeedback: true,
        hasSeenOnboarding: false,
        geminiAPIKey: nil,
        openAIAPIKey: nil,
        profitLossColorScheme: .default
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decode(String.self, forKey: .currency)
        startingBankroll = try c.decode(Double.self, forKey: .startingBankroll)
        lowBankrollAlert = try c.decodeIfPresent(Double.self, forKey: .lowBankrollAlert)
        defaultGameType = try c.decode(GameType.self, forKey: .defaultGameType)
        defaultVariant = try c.decodeIfPresent(String.self, forKey: .defaultVariant)
        defaultStakes = try c.decodeIfPresent(String.self, forKey: .defaultStakes)
        showHourlyRate = try c.decode(Bool.self, forKey: .showHourlyRate)
        hapticFeedback = try c.decode(Bool.self, forKey: .hapticFeedback)
        hasSeenOnboarding = try c.decode(Bool.self, forKey: .hasSeenOnboarding)
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey)
        openAIAPIKey = try c.decodeIfPresent(String.self, forKey: .openAIAPIKey)
        profitLossColorScheme = try c.decodeIfPresent(ProfitLossColorScheme.self, forKey: .profitLossColorScheme) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(startingBankroll, forKey: .startingBankroll)
        try c.encodeIfPresent(lowBankrollAlert, forKey: .lowBankrollAlert)
        try c.encode(defaultGameType, forKey: .defaultGameType)
        try c.encodeIfPresent(defaultVariant, forKey: .defaultVariant)
        try c.encodeIfPresent(defaultStakes, forKey: .defaultStakes)
        try c.encode(showHourlyRate, forKey: .showHourlyRate)
        try c.encode(hapticFeedback, forKey: .hapticFeedback)
        try c.encode(hasSeenOnboarding, forKey: .hasSeenOnboarding)
        try c.encodeIfPresent(geminiAPIKey, forKey: .geminiAPIKey)
        try c.encodeIfPresent(openAIAPIKey, forKey: .openAIAPIKey)
        try c.encode(profitLossColorScheme, forKey: .profitLossColorScheme)
    }
}
