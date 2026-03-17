//
//  SessionStore.swift
//  PokerTrackerIOS
//

import Foundation
import SwiftUI

enum ProfitBreakdownDimension: String, CaseIterable, Identifiable {
    case venue = "Venue"
    case gameType = "Game Type"
    case variant = "Variant"
    case stakes = "Stakes"
    case weekday = "Weekday"

    var id: String { rawValue }
}

struct ProfitBreakdownEntry: Identifiable, Equatable {
    let label: String
    let profit: Double
    let sessions: Int

    var id: String { label }
}

class SessionStore: ObservableObject {
    struct SessionsBackup: Codable {
        let version: Int
        let exportedAt: Date
        let sessions: [PokerSession]
    }

    enum BackupError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "The selected file is not a valid Poker Tracker backup."
            }
        }
    }

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
    private let saveUpdatedAtKey = "poker_sessions_updated_at"
    private let cloudSaveKey = "icloud_poker_sessions"
    private let cloudSaveUpdatedAtKey = "icloud_poker_sessions_updated_at"
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var isApplyingCloudSync = false
    private var cloudSyncUpdatedAt: TimeInterval?
    
    init() {
        loadSessionsLocal()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromCloudIfNewer()
        }
        DispatchQueue.main.async { [weak self] in
            self?.cloudStore.synchronize()
            self?.syncFromCloudIfNewer()
        }
    }

    deinit {
        if let observer = cloudObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Filtered Sessions
    /// Filtered sessions sorted by date descending (most recent first).
    var filteredSessions: [PokerSession] {
        var result = sessions
        let calendar = Calendar.current
        if let type = filterGameType {
            result = result.filter { $0.gameType == type }
        }
        if let from = filterDateFrom {
            let startOfDay = calendar.startOfDay(for: from)
            result = result.filter { $0.date >= startOfDay }
        }
        if let to = filterDateTo {
            let startOfDay = calendar.startOfDay(for: to)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? to
            result = result.filter { $0.date < nextDay }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    /// Sessions filtered for the list UI (game/date filters plus search text).
    var listSessions: [PokerSession] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return filteredSessions }

        let search = trimmedSearch.lowercased()
        return filteredSessions.filter { session in
            session.notes.lowercased().contains(search) ||
            (session.handNotes?.lowercased().contains(search) ?? false) ||
            (session.venue?.lowercased().contains(search) ?? false) ||
            (session.stakes?.lowercased().contains(search) ?? false) ||
            session.displayVariant.lowercased().contains(search) ||
            session.tags.contains(where: { $0.lowercased().contains(search) }) ||
            session.attachedHands.contains(where: { hand in
                hand.playerHands.joined(separator: " ").lowercased().contains(search) ||
                hand.resultSummary.joined(separator: " ").lowercased().contains(search) ||
                (hand.note?.lowercased().contains(search) ?? false)
            }) ||
            session.gameType.rawValue.lowercased().contains(search)
        }
    }

    var hasActiveListFilters: Bool {
        filterGameType != nil ||
        filterDateFrom != nil ||
        filterDateTo != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Core Stats
    var totalProfit: Double { filteredSessions.reduce(0) { $0 + $1.amount } }
    var totalSessions: Int { filteredSessions.count }
    var winCount: Int { filteredSessions.filter { $0.isWin }.count }
    var lossCount: Int { filteredSessions.filter { $0.isLoss }.count }
    var breakEvenCount: Int { filteredSessions.filter { $0.isBreakEven }.count }
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
            if session.isLoss { streak += 1 } else { break }
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
        return filteredDailyProfit.map { day, profit in
            running += profit
            return (day, running)
        }
    }

    /// Peak-to-trough bankroll drawdown over time (0 = at peak, negative = below peak)
    var drawdownOverTime: [(Date, Double)] {
        var running: Double = 0
        var peak: Double = 0
        return filteredDailyProfit.map { day, profit in
            running += profit
            peak = max(peak, running)
            return (day, running - peak)
        }
    }

    /// Weekday performance in locale order (includes empty weekdays with 0 sessions).
    /// average is average P/L per session for that weekday.
    var weekdayPerformance: [(label: String, weekday: Int, average: Double, sessions: Int, total: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session in
            cal.component(.weekday, from: session.date) // 1...7
        }

        let symbols = DateFormatter().shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let orderedWeekdays = (0..<7).map { offset in
            ((cal.firstWeekday - 1 + offset) % 7) + 1
        }

        return orderedWeekdays.map { weekday in
            let sessions = grouped[weekday] ?? []
            let total = sessions.reduce(0) { $0 + $1.amount }
            let count = sessions.count
            let avg = count > 0 ? total / Double(count) : 0
            return (
                label: symbols[weekday - 1],
                weekday: weekday,
                average: avg,
                sessions: count,
                total: total
            )
        }
    }

    func profitBreakdown(for dimension: ProfitBreakdownDimension) -> [ProfitBreakdownEntry] {
        switch dimension {
        case .venue:
            return groupedProfitBreakdown { session in
                VenueCleaner.clean(session.venue) ?? "Unknown Venue"
            }
        case .gameType:
            return groupedProfitBreakdown { session in
                session.gameType.rawValue
            }
        case .variant:
            return groupedProfitBreakdown { session in
                PokerSession.abbreviation(for: session.displayVariant)
            }
        case .stakes:
            return groupedProfitBreakdown { session in
                let trimmed = session.stakes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? "Unknown Stakes" : trimmed
            }
        case .weekday:
            return weekdayPerformance
                .filter { $0.sessions > 0 }
                .map { point in
                    ProfitBreakdownEntry(
                        label: point.label,
                        profit: point.total,
                        sessions: point.sessions
                    )
                }
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
    
    var lastSession: PokerSession? {
        sessions.max {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    
    /// Date range for charts: earliest session date through today
    var chartDateRange: (start: Date, end: Date)? {
        guard !filteredSessions.isEmpty else { return nil }
        let calendar = Calendar.current
        let first = filteredSessions.min(by: { $0.date < $1.date })!.date
        let last = filteredSessions.max(by: { $0.date < $1.date })!.date
        let today = calendar.startOfDay(for: Date())
        let end = endOfDay(for: max(last, today), using: calendar)
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
        let end = endOfDay(for: max(last, today), using: calendar)
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
        return (calendar.startOfDay(for: first), endOfDay(for: max(last, today), using: calendar))
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
        sessions = sortedSessions(sessions + [session])
    }
    
    func updateSession(_ session: PokerSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            var updated = sessions
            updated[i] = session
            sessions = sortedSessions(updated)
        }
    }

    func addAttachedHand(_ hand: PokerSession.AttachedHand, toSessionID id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].attachedHands.append(hand)
    }
    
    func deleteSession(_ session: PokerSession) {
        SessionImageStore.delete(imageIds: session.imageIds)
        sessions.removeAll { $0.id == session.id }
    }

    private func groupedProfitBreakdown(_ labelForSession: (PokerSession) -> String) -> [ProfitBreakdownEntry] {
        Dictionary(grouping: filteredSessions, by: labelForSession)
            .map { label, sessions in
                ProfitBreakdownEntry(
                    label: label,
                    profit: sessions.reduce(0) { $0 + $1.amount },
                    sessions: sessions.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.profit != rhs.profit { return lhs.profit > rhs.profit }
                if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
                return lhs.label < rhs.label
            }
    }
    
    
    // MARK: - Export
    func exportCSV(currency: String = "USD") -> String {
        func escapeCSV(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return value
        }

        var csv = "Date,Game Format,Variant,Amount,Hours,Stakes,Venue,Tags,Notes\n"
        for s in sessions.sorted(by: { $0.date > $1.date }) {
            let date = ISO8601DateFormatter().string(from: s.date)
            let amount = PokerSession.formatCurrency(s.amount, currency: currency)
            let hours = s.hoursPlayed.map { String($0) } ?? ""
            let stakes = s.stakes ?? ""
            let venue = s.venue ?? ""
            let variant = s.displayVariant
            let tags = s.tags.joined(separator: "; ")
            let notes = [s.notes, s.handNotes]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: "\n\n")
            let row = [
                escapeCSV(date),
                escapeCSV(s.gameType.rawValue),
                escapeCSV(variant),
                escapeCSV(amount),
                escapeCSV(hours),
                escapeCSV(stakes),
                escapeCSV(venue),
                escapeCSV(tags),
                escapeCSV(notes)
            ].joined(separator: ",")
            csv += "\(row)\n"
        }
        return csv
    }

    func exportBackupJSON() -> String? {
        let backup = SessionsBackup(version: 1, exportedAt: Date(), sessions: sessions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func restoreFromBackupJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let backup = try? decoder.decode(SessionsBackup.self, from: data) {
            replaceSessionsWithCleanup(backup.sessions)
            return sessions.count
        }

        // Backward compatibility: allow restoring raw [PokerSession] files.
        if let restored = try? decoder.decode([PokerSession].self, from: data) {
            replaceSessionsWithCleanup(restored)
            return sessions.count
        }

        throw BackupError.invalidFormat
    }
    
    private func loadSessionsLocal() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = decodeSessions(from: data) else {
            sessions = []
            return
        }
        sessions = sortedSessions(decoded)
    }
    
    private func saveSessions() {
        guard let encoded = try? JSONEncoder().encode(sessions) else { return }
        let updatedAt = cloudSyncUpdatedAt ?? Date().timeIntervalSince1970

        UserDefaults.standard.set(encoded, forKey: saveKey)
        UserDefaults.standard.set(updatedAt, forKey: saveUpdatedAtKey)

        guard !isApplyingCloudSync else { return }

        // NSUbiquitousKeyValueStore has tight value limits; skip oversized payloads.
        guard encoded.count <= 900_000 else { return }
        cloudStore.set(encoded, forKey: cloudSaveKey)
        cloudStore.set(updatedAt, forKey: cloudSaveUpdatedAtKey)
        cloudStore.synchronize()
    }

    private func syncFromCloudIfNewer() {
        let cloudUpdatedAt = cloudStore.double(forKey: cloudSaveUpdatedAtKey)
        let localUpdatedAt = UserDefaults.standard.double(forKey: saveUpdatedAtKey)
        guard cloudUpdatedAt > localUpdatedAt else { return }
        guard let cloudData = cloudStore.data(forKey: cloudSaveKey),
              let decoded = decodeSessions(from: cloudData) else { return }

        isApplyingCloudSync = true
        cloudSyncUpdatedAt = cloudUpdatedAt
        replaceSessionsWithCleanup(decoded)
        cloudSyncUpdatedAt = nil
        isApplyingCloudSync = false
    }

    private func decodeSessions(from data: Data) -> [PokerSession]? {
        try? JSONDecoder().decode([PokerSession].self, from: data)
    }

    private func replaceSessionsWithCleanup(_ restoredSessions: [PokerSession]) {
        let currentImageIDs = Set(sessions.flatMap(\.imageIds))
        let restoredImageIDs = Set(restoredSessions.flatMap(\.imageIds))
        let orphanedImageIDs = currentImageIDs.subtracting(restoredImageIDs)
        if !orphanedImageIDs.isEmpty {
            SessionImageStore.delete(imageIds: Array(orphanedImageIDs))
        }
        sessions = sortedSessions(restoredSessions)
    }

    private var filteredDailyProfit: [(Date, Double)] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.date)
        }
        .map { day, sessions in
            (day, sessions.reduce(0) { $0 + $1.amount })
        }
        .sorted { $0.0 < $1.0 }
    }

    private func endOfDay(for date: Date, using calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return nextDay.addingTimeInterval(-1)
    }

    private func sortedSessions(_ source: [PokerSession]) -> [PokerSession] {
        source
            .map { session in
                var normalized = session
                if let calculated = PokerSession.calculatedHours(from: normalized.startTime, to: normalized.endTime),
                   normalized.hoursPlayed == nil || (normalized.hoursPlayed ?? 0) <= 0 {
                    normalized.hoursPlayed = calculated
                }
                return normalized
            }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString > $1.id.uuidString
            }
    }
}
