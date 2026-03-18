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
    @State private var showingOddsCalculator = false
    @State private var sessionToEdit: PokerSession?
    @State private var sessionToDelete: PokerSession?
    @State private var preselectedAttachSessionID: UUID?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sessionStore.listSessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessionStore.listSessions) { session in
                            NavigationLink { SessionDetailView(session: session) } label: {
                                SessionRowView(session: session, displayNumber: sessionStore.displayNumber(for: session), currency: settingsStore.settings.currency)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                    if settingsStore.settings.confirmBeforeDelete {
                                        sessionToDelete = session
                                    } else {
                                        sessionStore.deleteSession(session)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                Button {
                                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                    sessionToEdit = session
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                                Button {
                                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                                    preselectedAttachSessionID = session.id
                                    showingOddsCalculator = true
                                } label: {
                                    Label("Add Hand", systemImage: "percent")
                                }
                                .tint(AppTheme.accent)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .animation(AppTheme.smoothSpring, value: sessionStore.listSessions.count)
                }

                if sessionStore.hasActiveSessionFilters {
                    activeFiltersBar
                }
                searchBar
            }
            .animation(AppTheme.smoothSpring, value: sessionStore.listSessions.isEmpty)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Sessions")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            showingAddSession = true
                        } label: { Label("Add Session", systemImage: "plus") }
                        Button {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            preselectedAttachSessionID = nil
                            showingOddsCalculator = true
                        } label: { Label("Add Hand", systemImage: "percent") }
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
            .sheet(isPresented: $showingOddsCalculator, onDismiss: {
                preselectedAttachSessionID = nil
            }) {
                OddsCalculatorView(preselectedSessionID: preselectedAttachSessionID)
            }
            .sheet(isPresented: $showingFilters) {
                FilterView()
                    .environmentObject(sessionStore)
                    .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $sessionToEdit) { session in EditSessionView(session: session) }
            .alert("Delete Session?", isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
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
        let showingNoMatches = sessionStore.hasActiveListFilters && !sessionStore.sessions.isEmpty

        return VStack(spacing: 14) {
            Spacer()

            Image(systemName: showingNoMatches ? "magnifyingglass" : "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.35))

            Text(showingNoMatches ? "No Matching Sessions" : "No Sessions Yet")
                .font(.headline)

            if showingNoMatches {
                Text("Try clearing your search or filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log your first session from the Home tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    showingAddSession = true
                } label: {
                    Label("Add Session", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.accent))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
            TextField("Search notes, venue, stakes...", text: $sessionStore.searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !sessionStore.searchText.isEmpty {
                Button {
                    sessionStore.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sessionStore.activeFilterLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.cardBackground))
                }

                Button("Clear") {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    sessionStore.clearFilters()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var gameType: GameType?
    @State private var variant: String?
    @State private var stakes: String?
    @State private var venue: String?
    @State private var tag: String?
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
                Section("Session Details") {
                    Picker("Variant", selection: $variant) {
                        Text("All").tag(nil as String?)
                        ForEach(sessionStore.availableVariants, id: \.self) { option in
                            Text(option).tag(option as String?)
                        }
                    }

                    Picker("Stakes", selection: $stakes) {
                        Text("All").tag(nil as String?)
                        ForEach(sessionStore.availableStakes, id: \.self) { option in
                            Text(option).tag(option as String?)
                        }
                    }

                    Picker("Venue", selection: $venue) {
                        Text("All").tag(nil as String?)
                        ForEach(sessionStore.availableVenues, id: \.self) { option in
                            Text(option).tag(option as String?)
                        }
                    }

                    Picker("Tag", selection: $tag) {
                        Text("All").tag(nil as String?)
                        ForEach(sessionStore.availableTags, id: \.self) { option in
                            Text(option).tag(option as String?)
                        }
                    }
                }
                Section("Date Range") {
                    Toggle("From Date", isOn: $useDateFrom)
                    if useDateFrom { DatePicker("From", selection: $dateFrom, displayedComponents: .date) }
                    Toggle("To Date", isOn: $useDateTo)
                    if useDateTo { DatePicker("To", selection: $dateTo, displayedComponents: .date) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Filters")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        gameType = nil
                        variant = nil
                        stakes = nil
                        venue = nil
                        tag = nil
                        useDateFrom = false
                        useDateTo = false
                        sessionStore.clearFilters()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
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
                        sessionStore.filterVariant = variant
                        sessionStore.filterStakes = stakes
                        sessionStore.filterVenue = venue
                        sessionStore.filterTag = tag
                        dismiss()
                    }
                }
            }
            .onAppear {
                gameType = sessionStore.filterGameType
                variant = sessionStore.filterVariant
                stakes = sessionStore.filterStakes
                venue = sessionStore.filterVenue
                tag = sessionStore.filterTag
                useDateFrom = sessionStore.filterDateFrom != nil
                useDateTo = sessionStore.filterDateTo != nil
                if let from = sessionStore.filterDateFrom { dateFrom = from }
                if let to = sessionStore.filterDateTo { dateTo = to }
            }
        }
    }
}

private struct SessionsListView_Previews: PreviewProvider {
    static var previews: some View {
        SessionsListView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
