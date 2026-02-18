//
//  SessionStore.swift
//  PokerTrackerIOS
//

import Foundation
import SwiftUI

class SessionStore: ObservableObject {
    @Published var sessions: [PokerSession] = [] {
        didSet {
            saveSessions()
            dataVersion += 1
        }
    }
    @Published private(set) var dataVersion: Int = 0
    @Published var filterGameType: GameType?
    @Published var filterDateFrom: Date?
    @Published var filterDateTo: Date?
    @Published var searchText: String = ""
    
    private let saveKey = "poker_sessions"
    
    init() {
        loadSessions()
    }
    
    // MARK: - Filtered Sessions
    /// Filtered sessions sorted by date ascending (earliest first) so display numbers align: #1 at top, #N at bottom
    var filteredSessions: [PokerSession] {
        var result = sessions
        if let type = filterGameType {
            result = result.filter { $0.gameType == type }
        }
        if let from = filterDateFrom {
            result = result.filter { $0.date >= from }
        }
        if let to = filterDateTo {
            result = result.filter { $0.date <= to }
        }
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.notes.lowercased().contains(search) ||
                ($0.venue?.lowercased().contains(search) ?? false) ||
                ($0.stakes?.lowercased().contains(search) ?? false) ||
                ($0.variant?.lowercased().contains(search) ?? false) ||
                $0.gameType.rawValue.lowercased().contains(search)
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString > $1.id.uuidString
        }
    }
    
    // MARK: - Core Stats
    var totalProfit: Double { filteredSessions.reduce(0) { $0 + $1.amount } }
    var totalSessions: Int { filteredSessions.count }
    var winCount: Int { filteredSessions.filter { $0.isWin }.count }
    var lossCount: Int { filteredSessions.filter { !$0.isWin }.count }
    var winRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(winCount) / Double(totalSessions) * 100
    }
    
    // MARK: - Advanced Stats
    var totalHoursPlayed: Double {
        filteredSessions.compactMap { $0.hoursPlayed }.reduce(0, +)
    }
    var hourlyRate: Double? {
        guard totalHoursPlayed > 0 else { return nil }
        return totalProfit / totalHoursPlayed
    }
    var averageSession: Double {
        guard totalSessions > 0 else { return 0 }
        return totalProfit / Double(totalSessions)
    }
    var bestSession: PokerSession? { filteredSessions.max(by: { $0.amount < $1.amount }) }
    var worstSession: PokerSession? { filteredSessions.min(by: { $0.amount < $1.amount }) }
    
    // MARK: - Streaks
    var currentWinStreak: Int {
        var streak = 0
        for session in filteredSessions.sorted(by: { $0.date > $1.date }) {
            if session.isWin { streak += 1 } else { break }
        }
        return streak
    }
    var currentLossStreak: Int {
        var streak = 0
        for session in filteredSessions.sorted(by: { $0.date > $1.date }) {
            if !session.isWin { streak += 1 } else { break }
        }
        return streak
    }
    var longestWinStreak: Int {
        var maxStreak = 0, current = 0
        for session in filteredSessions.sorted(by: { $0.date < $1.date }) {
            if session.isWin { current += 1; maxStreak = max(maxStreak, current) }
            else { current = 0 }
        }
        return maxStreak
    }
    
    // MARK: - Chart Data
    var profitOverTime: [(Date, Double)] {
        var running: Double = 0
        return filteredSessions.sorted { $0.date < $1.date }.map { session in
            running += session.amount
            return (session.date, running)
        }
    }
    
    var sessionsByGameType: [(GameType, Int)] {
        Dictionary(grouping: filteredSessions, by: { $0.gameType })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }
    
    var sessionsByVariant: [(String, Int, Double)] {
        Dictionary(grouping: filteredSessions, by: { $0.displayVariant })
            .map { ($0.key, $0.value.count, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }
    
    var monthlyProfit: [(String, Double)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.date)) ?? session.date
        }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.0 < $1.0 }
            .map { (formatter.string(from: $0.0), $0.1) }
    }
    
    /// Monthly profit with Date for chart domain (month start dates)
    var monthlyProfitWithDates: [(Date, Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.date)) ?? session.date
        }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.0 < $1.0 }
    }
    
    var lastSession: PokerSession? { sessions.first }
    
    /// Date range for charts: earliest session date through today
    var chartDateRange: (start: Date, end: Date)? {
        guard !filteredSessions.isEmpty else { return nil }
        let calendar = Calendar.current
        let first = filteredSessions.min(by: { $0.date < $1.date })!.date
        let last = filteredSessions.max(by: { $0.date < $1.date })!.date
        let today = calendar.startOfDay(for: Date())
        let end = last > today ? last : today
        let start = calendar.startOfDay(for: first)
        return (start, end)
    }
    
    /// Domain for monthly chart: only months with data, with padding
    var monthlyChartDomain: (start: Date, end: Date)? {
        let months = monthlyProfitWithDates
        guard let first = months.first?.0, let last = months.last?.0 else { return nil }
        let calendar = Calendar.current
        let paddingStart = calendar.date(byAdding: .month, value: -1, to: first) ?? first
        let paddingEnd = calendar.date(byAdding: .month, value: 1, to: last) ?? last
        return (paddingStart, paddingEnd)
    }
    
    /// Domain for cumulative profit: earliest session through today
    var cumulativeProfitDomain: (start: Date, end: Date)? {
        guard !filteredSessions.isEmpty else { return nil }
        let calendar = Calendar.current
        let first = filteredSessions.min(by: { $0.date < $1.date })!.date
        let last = filteredSessions.max(by: { $0.date < $1.date })!.date
        let today = calendar.startOfDay(for: Date())
        let end = last > today ? last : today
        return (calendar.startOfDay(for: first), end)
    }
    
    /// Earliest session date in filtered set
    var firstSessionDate: Date? {
        filteredSessions.min(by: { $0.date < $1.date })?.date
    }

    /// Earliest session date across all sessions (unfiltered)
    var earliestSessionDate: Date? {
        sessions.min(by: { $0.date < $1.date })?.date
    }
    
    /// Date range of all sessions (unfiltered) for preset bounds
    var allSessionsDateRange: (start: Date, end: Date)? {
        guard !sessions.isEmpty else { return nil }
        let first = sessions.min(by: { $0.date < $1.date })!.date
        let last = sessions.max(by: { $0.date < $1.date })!.date
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (first, last > today ? last : today)
    }
    
    var thisMonthProfit: Double {
        let calendar = Calendar.current
        let now = Date()
        return filteredSessions
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// Sessions on a given calendar day (uses all sessions, not filtered)
    func sessions(on date: Date) -> [PokerSession] {
        sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }
    
    /// Total profit for a given calendar day
    func dailyProfit(on date: Date) -> Double {
        sessions(on: date).reduce(0) { $0 + $1.amount }
    }
    
    /// Total profit for a given month
    func monthlyProfit(for monthStart: Date) -> Double {
        let cal = Calendar.current
        return sessions
            .filter { cal.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }
    
    // MARK: - Session Numbering (dynamic: earliest = #1, latest = #N)
    
    /// Sessions sorted earliest to latest (used for display numbers; uses all sessions for stable numbering)
    var sessionsByDateAscending: [PokerSession] {
        sessions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    
    /// Display number for a session (1-based, earliest = #1)
    func displayNumber(for session: PokerSession) -> Int? {
        let sorted = sessionsByDateAscending
        guard let idx = sorted.firstIndex(where: { $0.id == session.id }) else { return nil }
        return idx + 1
    }
    
    /// Look up a session by its display number (#1 = earliest, #2 = next, etc.)
    func session(byNumber num: Int) -> PokerSession? {
        let sorted = sessionsByDateAscending
        guard num >= 1, num <= sorted.count else { return nil }
        return sorted[num - 1]
    }
    
    // MARK: - CRUD
    func addSession(_ session: PokerSession) {
        sessions.insert(session, at: 0)
    }
    
    func updateSession(_ session: PokerSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
        }
    }
    
    func deleteSession(_ session: PokerSession) {
        SessionImageStore.delete(imageIds: session.imageIds)
        sessions.removeAll { $0.id == session.id }
    }
    
    func deleteSessions(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredSessions[$0] }
        for s in toDelete { deleteSession(s) }
    }
    
    // MARK: - Export
    func exportCSV(currency: String = "USD") -> String {
        var csv = "Date,Game Format,Variant,Amount,Hours,Stakes,Venue,Notes\n"
        for s in filteredSessions.sorted(by: { $0.date > $1.date }) {
            let date = ISO8601DateFormatter().string(from: s.date)
            let amount = PokerSession.formatCurrency(s.amount, currency: currency)
            let hours = s.hoursPlayed.map { String($0) } ?? ""
            let stakes = s.stakes ?? ""
            let venue = s.venue ?? ""
            let variant = s.displayVariant
            let notes = (s.notes + (s.handNotes ?? "")).replacingOccurrences(of: ",", with: ";")
            csv += "\(date),\(s.gameType.rawValue),\(variant),\(amount),\(hours),\(stakes),\(venue),\(notes)\n"
        }
        return csv
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([PokerSession].self, from: data) else {
            sessions = []
            return
        }
        sessions = decoded.sorted { $0.date > $1.date }
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
}
