//
//  MainTabView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AnalyticsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(0)
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(1)
            OddsCalculatorView()
                .tabItem { Label("Odds", systemImage: "percent") }
                .tag(2)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(3)
            SessionsListView()
                .tabItem { Label("Sessions", systemImage: "list.bullet") }
                .tag(4)
        }
        .tint(AppTheme.accent)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea(.all))
    }
}

#Preview {
    MainTabView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
        .environmentObject(SubscriptionStore.shared)
}
