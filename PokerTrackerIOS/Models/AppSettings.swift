//
//  AppSettings.swift
//  PokerTrackerIOS
//

import Foundation

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
        openAIAPIKey: nil
    )
}
