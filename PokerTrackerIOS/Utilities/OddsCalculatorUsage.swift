//
//  OddsCalculatorUsage.swift
//  PokerTrackerIOS
//
//  Tracks free uses of Odds Calculator (20 total). Subscribers get unlimited.
//

import Foundation

enum OddsCalculatorUsage {
    private static let key = "odds_calculator_uses_used"
    static let freeUseLimit = 20

    static var usesUsed: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: key)
            return min(max(v, 0), freeUseLimit)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0), freeUseLimit), forKey: key)
        }
    }

    static var usesRemaining: Int {
        max(0, freeUseLimit - usesUsed)
    }

    static var hasFreeUsesRemaining: Bool {
        usesRemaining > 0
    }

    static func consumeOne() {
        usesUsed += 1
    }
}
