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
            SessionsListView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(AppTheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea(.all))
    }
}

#Preview {
    MainTabView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
