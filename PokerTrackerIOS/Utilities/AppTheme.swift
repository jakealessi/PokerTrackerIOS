//
//  AppTheme.swift
//  PokerTrackerIOS
//
//  Adapts to light/dark mode
//

import SwiftUI

enum AppTheme {
    static let accent = Color.blue
    static let secondaryText = Color.secondary
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

    static let cardCornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10

    static let smoothSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    static let cardShadow = Shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    static let subtleShadow = Shadow(color: .black.opacity(0.04), radius: 4, y: 1)
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(
                        color: AppTheme.cardShadow.color,
                        radius: AppTheme.cardShadow.radius,
                        y: AppTheme.cardShadow.y
                    )
            )
    }

    func subtleCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(
                        color: AppTheme.subtleShadow.color,
                        radius: AppTheme.subtleShadow.radius,
                        y: AppTheme.subtleShadow.y
                    )
            )
    }
}
