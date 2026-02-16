//
//  ContentView.swift
//  PokerTrackerIOS
//
//  Legacy - MainTabView is now the primary entry. Kept for preview compatibility.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}

#Preview {
    ContentView()
}
