//
//  CalendarView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var displayMonth: Date = Date()
    @State private var selectedDate: Date?
    @State private var showingAddSession = false
    
    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigation
                weekdayHeaders
                monthGrid
                
                if let date = selectedDate {
                    daySessionsSection(for: date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSession = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) { AddSessionView() }
        }
    }
    
    private var monthNavigation: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text(monthYearString(from: displayMonth))
                .font(.headline)
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
    }
    
    private var weekdayHeaders: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, date in
                if let date = date {
                    DayCell(
                        date: date,
                        isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                        isToday: calendar.isDateInToday(date),
                        sessions: sessionStore.sessions(on: date),
                        isInDisplayMonth: calendar.isDate(date, equalTo: displayMonth, toGranularity: .month)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    }
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func daySessionsSection(for date: Date) -> some View {
        let sessionsOnDay = sessionStore.sessions(on: date)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(date, style: .date)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button("Clear") {
                    withAnimation { selectedDate = nil }
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
                List {
                    ForEach(sessionsOnDay) { session in
                        NavigationLink { SessionDetailView(session: session) } label: {
                            SessionRowView(
                                session: session,
                                displayNumber: sessionStore.displayNumber(for: session),
                                currency: settingsStore.settings.currency
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, 8)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .padding()
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = firstWeekday - calendar.firstWeekday
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
                    let day = range.lowerBound + dayIndex
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
    let sessions: [PokerSession]
    let isInDisplayMonth: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .bold : .medium))
                    .foregroundStyle(foregroundColor)
                
                if !sessions.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(sessions.prefix(3)) { session in
                            Circle()
                                .fill(session.isWin ? Color.green : Color.red)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var foregroundColor: Color {
        if !isInDisplayMonth { return AppTheme.secondaryText.opacity(0.5) }
        if isSelected { return .white }
        return .primary
    }
    
    private var backgroundColor: Color {
        if isSelected { return AppTheme.accent }
        if isToday { return AppTheme.accent.opacity(0.2) }
        return Color.clear
    }
}

#Preview {
    CalendarView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
