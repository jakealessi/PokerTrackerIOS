//
//  AISessionCrafterUsage.swift
//  PokerTrackerIOS
//
//  Tracks free uses of AI Session Crafter (20 total). Subscribers get unlimited.
//

import Foundation

enum AISessionCrafterUsage {
    private static let key = "ai_session_crafter_uses_used"
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
