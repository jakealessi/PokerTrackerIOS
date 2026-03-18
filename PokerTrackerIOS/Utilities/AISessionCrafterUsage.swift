//
//  AISessionCrafterUsage.swift
//  PokerTrackerIOS
//
//  Tracks free uses of AI Session Crafter (10 total). Subscribers get unlimited.
//

import Foundation

enum AISessionCrafterUsage {
    private static let key = "ai_session_crafter_uses_used"
    private static let queue = DispatchQueue(label: "AISessionCrafterUsage")
    static let freeUseLimit = 10

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
