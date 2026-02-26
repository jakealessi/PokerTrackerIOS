//
//  SessionsListView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingAddSession = false
    @State private var showingFilters = false
    @State private var showingSettings = false
    @State private var sessionToEdit: PokerSession?
    @State private var sessionToDelete: PokerSession?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sessionStore.filteredSessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessionStore.filteredSessions) { session in
                            NavigationLink { SessionDetailView(session: session) } label: {
                                SessionRowView(session: session, displayNumber: sessionStore.displayNumber(for: session), currency: settingsStore.settings.currency)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if settingsStore.settings.confirmBeforeDelete {
                                        sessionToDelete = session
                                    } else {
                                        sessionStore.deleteSession(session)
                                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { sessionToEdit = session } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .animation(AppTheme.smoothSpring, value: sessionStore.filteredSessions.count)
                }
                
                searchBar
            }
            .animation(AppTheme.smoothSpring, value: sessionStore.filteredSessions.isEmpty)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Sessions")
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAddSession = true } label: { Label("Add Session", systemImage: "plus") }
                        Button { showingFilters = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFilters) { FilterView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $sessionToEdit) { session in EditSessionView(session: session) }
            .alert("Delete Session?", isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        sessionStore.deleteSession(session)
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    }
                    sessionToDelete = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(sessionStore.searchText.isEmpty ? "No sessions yet" : "No matching sessions")
                .font(.headline)
                .foregroundStyle(AppTheme.secondaryText)
            if sessionStore.searchText.isEmpty {
                Button("Add Session") { showingAddSession = true }
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField("Search notes, venue, stakes", text: $sessionStore.searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(8)
        .padding()
    }
}

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @State private var gameType: GameType?
    @State private var useDateFrom = false
    @State private var useDateTo = false
    @State private var dateFrom = Date().addingTimeInterval(-30*24*3600)
    @State private var dateTo = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Game Format") {
                    Picker("Filter by", selection: $gameType) {
                        Text("All").tag(nil as GameType?)
                        ForEach(GameType.formatOptions, id: \.self) { Text($0.rawValue).tag($0 as GameType?) }
                    }
                }
                Section("Date Range") {
                    Toggle("From Date", isOn: $useDateFrom)
                    if useDateFrom { DatePicker("From", selection: $dateFrom, displayedComponents: .date) }
                    Toggle("To Date", isOn: $useDateTo)
                    if useDateTo { DatePicker("To", selection: $dateTo, displayedComponents: .date) }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Filters")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        gameType = nil
                        useDateFrom = false
                        useDateTo = false
                        sessionStore.filterGameType = nil
                        sessionStore.filterDateFrom = nil
                        sessionStore.filterDateTo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let finalFrom = useDateFrom ? dateFrom : nil
                        let finalTo = useDateTo ? dateTo : nil
                        if let from = finalFrom, let to = finalTo, from > to {
                            sessionStore.filterDateFrom = to
                            sessionStore.filterDateTo = from
                        } else {
                            sessionStore.filterDateFrom = finalFrom
                            sessionStore.filterDateTo = finalTo
                        }
                        sessionStore.filterGameType = gameType
                        dismiss()
                    }
                }
            }
            .onAppear {
                gameType = sessionStore.filterGameType
                useDateFrom = sessionStore.filterDateFrom != nil
                useDateTo = sessionStore.filterDateTo != nil
                if let from = sessionStore.filterDateFrom { dateFrom = from }
                if let to = sessionStore.filterDateTo { dateTo = to }
            }
        }
    }
}

#Preview {
    SessionsListView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
