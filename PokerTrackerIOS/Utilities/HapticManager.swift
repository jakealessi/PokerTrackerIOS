//
//  HapticManager.swift
//  PokerTrackerIOS
//
//  Haptic feedback helper
//

import SwiftUI

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    
    static func success() {
        notification(.success)
    }
    
    static func lightTap() {
        impact(.light)
    }
}
