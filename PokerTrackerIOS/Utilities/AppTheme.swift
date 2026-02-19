//
//  AppTheme.swift
//  PokerTrackerIOS
//
//  Adapts to light/dark mode
//

import SwiftUI

enum AppTheme {
    static let background = Color(UIColor.systemGroupedBackground)
    static let accent = Color.blue
    static let secondaryText = Color.secondary
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

    static let cardCornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 10

    /// Smooth spring for UI transitions (buttons, selections, panels)
    static let smoothSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// Quick spring for immediate feedback (taps, toggles)
    static let quickSpring = Animation.spring(response: 0.25, dampingFraction: 0.8)
}
