//
//  OddsCalculatorUsage.swift
//  PokerTrackerIOS
//
//  Tracks free uses of Odds Calculator (15 total). Subscribers get unlimited.
//

import Foundation

enum OddsCalculatorUsage {
    private static let key = "odds_calculator_uses_used"
    private static let queue = DispatchQueue(label: "OddsCalculatorUsage")
    static let freeUseLimit = 15

    static var usesUsed: Int {
        get {
            queue.sync {
                let v = UserDefaults.standard.integer(forKey: key)
                return min(max(v, 0), freeUseLimit)
            }
        }
        set {
            queue.sync {
                UserDefaults.standard.set(min(max(newValue, 0), freeUseLimit), forKey: key)
            }
        }
    }

    static var usesRemaining: Int {
        max(0, freeUseLimit - usesUsed)
    }

    static var hasFreeUsesRemaining: Bool {
        usesRemaining > 0
    }

    static func consumeOne() {
        queue.sync {
            let v = UserDefaults.standard.integer(forKey: key)
            let next = min(max(v + 1, 0), freeUseLimit)
            UserDefaults.standard.set(next, forKey: key)
        }
    }
}
