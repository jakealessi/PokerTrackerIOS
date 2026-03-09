//
//  CalendarView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedDate: Date?
    @State private var showingAddSession = false
    @State private var showingSettings = false
    @State private var scrollPosition: Date?
    @State private var didInitialCenter = false
    
    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    /// Range of months: from first session's month through current month + 2
    private var monthRange: [Date] {
        guard let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else { return [] }
        let startMonth: Date
        if let earliest = sessionStore.earliestSessionDate {
            startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: earliest)) ?? thisMonth
        } else {
            startMonth = calendar.date(byAdding: .month, value: -12, to: thisMonth) ?? thisMonth
        }
        var months: [Date] = []
        var current = startMonth
        let endMonth = calendar.date(byAdding: .month, value: 2, to: thisMonth) ?? thisMonth
        while current <= endMonth {
            months.append(current)
            current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
        }
        return months
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(monthRange, id: \.self) { monthStart in
                            monthBlock(for: monthStart)
                                .id(monthStart)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scrollTargetLayout()
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .task {
                    // Avoid first-open "slightly off-center" glitches by centering only after
                    // the initial layout pass has happened (and doing it without animation).
                    guard !didInitialCenter else { return }
                    didInitialCenter = true
                    
                    guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else { return }
                    scrollPosition = month
                    
                    // One extra tick helps when content height settles (nav bar / safe area).
                    await Task.yield()
                    scrollPosition = month
                }
                .onChange(of: selectedDate) { _, newDate in
                    guard let date = newDate,
                          let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { return }
                    scrollPosition = monthStart
                }
                
                if let date = selectedDate {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        daySessionsSection(for: date)
                            .id(date)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                    }
                }
            }
            .animation(AppTheme.smoothSpring, value: selectedDate?.timeIntervalSince1970)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Calendar")
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button("Today") {
                            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))
                            scrollPosition = month
                            withAnimation(AppTheme.smoothSpring) {
                                selectedDate = Date()
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        Button { showingAddSession = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    private func monthBlock(for monthStart: Date) -> some View {
        let monthlyTotal = sessionStore.monthlyProfit(for: monthStart)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthYearString(from: monthStart))
                    .font(.headline)
                if monthlyTotal != 0 {
                    Text(formatShortAmount(monthlyTotal))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(monthlyTotal >= 0 ? settingsStore.settings.profitLossColorScheme.winColor : settingsStore.settings.profitLossColorScheme.lossColor)
                        .padding(.leading, 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ForEach(Array(daysInMonth(displayMonth: monthStart).enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                            isToday: calendar.isDateInToday(date),
                            dailyProfit: sessionStore.dailyProfit(on: date),
                            isInDisplayMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month),
                            currency: settingsStore.settings.currency,
                            winColor: settingsStore.settings.profitLossColorScheme.winColor,
                            lossColor: settingsStore.settings.profitLossColorScheme.lossColor
                        ) {
                            withAnimation(AppTheme.smoothSpring) {
                                selectedDate = date
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func daySessionsSection(for date: Date) -> some View {
        let sessionsOnDay = sessionStore.sessions(on: date)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(sessionsOnDay.count) Session\(sessionsOnDay.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear") {
                    withAnimation(AppTheme.smoothSpring) {
                        selectedDate = nil
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal)
            
            if sessionsOnDay.isEmpty {
                Text("No sessions this day")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                let rows = LazyVStack(spacing: 0) {
                    ForEach(sessionsOnDay) { session in
                        NavigationLink { SessionDetailView(session: session) } label: {
                            SessionRowView(
                                session: session,
                                displayNumber: sessionStore.displayNumber(for: session),
                                currency: settingsStore.settings.currency
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .animation(AppTheme.smoothSpring, value: sessionsOnDay.map(\.id))

                if sessionsOnDay.count <= 3 {
                    rows
                } else {
                    ScrollView {
                        rows
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
        .padding(.top, 8)
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        .padding()
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func formatShortAmount(_ amount: Double) -> String {
        if amount == 0 { return "" }
        let prefix = amount > 0 ? "+" : ""
        return prefix + PokerSession.formatCompactCurrency(abs(amount), currency: settingsStore.settings.currency)
    }
    
    private func daysInMonth(displayMonth: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        // Keep leading blanks in [0, 6] regardless of locale first weekday.
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalCells = leadingBlanks + range.count
        let rows = (totalCells + 6) / 7
        let cellCount = rows * 7
        
        var days: [Date?] = []
        for i in 0..<cellCount {
            if i < leadingBlanks {
                days.append(nil)
            } else {
                let dayIndex = i - leadingBlanks
                if dayIndex < range.count {
                    if let date = calendar.date(byAdding: .day, value: dayIndex, to: firstDay) {
                        days.append(date)
                    } else {
                        days.append(nil)
                    }
                } else {
                    days.append(nil)
                }
            }
        }
        return days
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let dailyProfit: Double
    let isInDisplayMonth: Bool
    let currency: String
    let winColor: Color
    let lossColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 15, weight: isToday ? .bold : .medium))
                    .foregroundStyle(dateTextColor)
                
                if dailyProfit != 0 {
                    Text(formatDailyAmount(dailyProfit))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(amountTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.smoothSpring, value: isSelected)
    }
    
    private func formatDailyAmount(_ amount: Double) -> String {
        PokerSession.formatCompactCurrency(abs(amount), currency: currency)
    }
    
    private var dateTextColor: Color {
        if !isInDisplayMonth { return Color.secondary.opacity(0.6) }
        if isSelected { return .white }
        return .primary
    }
    
    private var amountTextColor: Color {
        if isSelected { return .white.opacity(0.9) }
        if dailyProfit > 0 { return winColor }
        return lossColor
    }
    
    /// Apple-style: subtle tints for P/L, accent for selected
    private var cellBackground: some View {
        Group {
            if isSelected {
                AppTheme.accent
            } else if dailyProfit > 0 {
                winColor.opacity(0.15)
            } else if dailyProfit < 0 {
                lossColor.opacity(0.15)
            } else if isToday {
                AppTheme.accent.opacity(0.12)
            } else {
                Color.clear
            }
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
