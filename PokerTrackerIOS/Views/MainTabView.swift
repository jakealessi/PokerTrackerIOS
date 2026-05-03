//
//  MainTabView.swift
//  PokerTrackerIOS
//

import SwiftUI

final class AppRouteController: ObservableObject {
    @Published var pendingRoute: PokerWidgetRoute?
}

struct MainTabView: View {
    @EnvironmentObject var routeController: AppRouteController
    @State private var selectedTab = 1
    @State private var showingManualSession = false
    
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
        .sheet(isPresented: $showingManualSession) {
            AddSessionView()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            handleRoute(routeController.pendingRoute)
        }
        .onChange(of: routeController.pendingRoute) { _, route in
            handleRoute(route)
        }
    }

    private func handleRoute(_ route: PokerWidgetRoute?) {
        guard let route else { return }

        switch route {
        case .home:
            selectedTab = 1
        case .stats:
            selectedTab = 0
        case .odds:
            selectedTab = 2
        case .aiLog:
            selectedTab = 1
        case .manualLog:
            selectedTab = 1
            showingManualSession = false
            DispatchQueue.main.async {
                showingManualSession = true
            }
        case .calendar:
            selectedTab = 3
        case .sessions:
            selectedTab = 4
        }

        routeController.pendingRoute = nil
    }
}

private struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
            .environmentObject(SubscriptionStore.shared)
            .environmentObject(AppRouteController())
    }
}
