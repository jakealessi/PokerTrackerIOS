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

enum HourlyRateBreakdownDimension: String, CaseIterable, Identifiable {
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

struct HourlyRateBreakdownEntry: Identifiable, Equatable {
    let label: String
    let totalProfit: Double
    let totalHours: Double
    let sessions: Int

    var id: String { label }

    var hourlyRate: Double {
        guard totalHours > 0 else { return 0 }
        return totalProfit / totalHours
    }
}

struct VenueQuickOption: Identifiable, Equatable {
    enum Source: Equatable {
        case manual
        case automatic(sessionCount: Int)
    }

    let venue: String
    let source: Source

    var id: String { VenueCleaner.key(for: venue) ?? venue }
}

class SessionStore: ObservableObject {
    static let automaticVenueQuickOptionThreshold = 3
    static let cloudBackupPayloadLimitBytes = 900_000
    private static let supportedCurrencySymbolsForStakes: [String] = Array(Set(SupportedCurrency.all.map(\.symbol)))
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs > rhs
        }

    enum CloudBackupState: Equatable {
        case synced
        case notSignedIn
        case backupTooLarge
        case neverSynced
        case syncing
        case unavailable
    }

    struct CloudBackupStatus: Equatable {
        let state: CloudBackupState
        let lastSyncedAt: Date?
        let payloadBytes: Int
        let payloadLimitBytes: Int
    }

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
            guard !isBootstrapping else { return }
            saveSessions()
            dataVersion += 1
        }
    }
    @Published private(set) var dataVersion: Int = 0
    @Published var filterGameType: GameType?
    @Published var filterVariant: String?
    @Published var filterStakes: String?
    @Published var filterVenue: String?
    @Published var filterTag: String?
    @Published var filterDateFrom: Date?
    @Published var filterDateTo: Date?
    @Published var searchText: String = ""
    @Published private(set) var cloudBackupStatus = CloudBackupStatus(
        state: .neverSynced,
        lastSyncedAt: nil,
        payloadBytes: 0,
        payloadLimitBytes: SessionStore.cloudBackupPayloadLimitBytes
    )
    
    private let saveKey = "poker_sessions"
    private let saveUpdatedAtKey = "poker_sessions_updated_at"
    private let cloudSaveKey = "icloud_poker_sessions"
    private let cloudSaveUpdatedAtKey = "icloud_poker_sessions_updated_at"
    private let lastCloudSyncAtKey = "poker_sessions_last_cloud_sync_at"
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var isApplyingCloudSync = false
    private var cloudSyncUpdatedAt: TimeInterval?
    private var isBootstrapping = true
    
    init() {
        loadSessionsLocal()
        refreshCloudBackupStatus()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromCloudIfNewer()
        }
        isBootstrapping = false
        DispatchQueue.main.async { [weak self] in
            self?.cloudStore.synchronize()
            self?.syncFromCloudIfNewer()
            self?.refreshCloudBackupStatus()
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
        if let variant = filterVariant {
            result = result.filter {
                $0.displayVariant.compare(variant, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        if let stakes = filterStakes {
            result = result.filter {
                ($0.stakes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(stakes, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        if let venue = filterVenue {
            result = result.filter {
                (VenueCleaner.clean($0.venue) ?? "")
                    .compare(venue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        if let tag = filterTag {
            result = result.filter { session in
                session.tags.contains {
                    $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
            }
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
        return sortedSessionsDescending(result)
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
            session.displayGameType.lowercased().contains(search) ||
            session.tags.contains(where: { $0.lowercased().contains(search) }) ||
            session.expenseEntries.contains(where: { $0.label.lowercased().contains(search) }) ||
            session.attachedHands.contains(where: { hand in
                hand.playerHands.joined(separator: " ").lowercased().contains(search) ||
                hand.resultSummary.joined(separator: " ").lowercased().contains(search) ||
                (hand.note?.lowercased().contains(search) ?? false)
            })
        }
    }

    var hasActiveListFilters: Bool {
        filterGameType != nil ||
        filterVariant != nil ||
        filterStakes != nil ||
        filterVenue != nil ||
        filterTag != nil ||
        filterDateFrom != nil ||
        filterDateTo != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveSessionFilters: Bool {
        filterGameType != nil ||
        filterVariant != nil ||
        filterStakes != nil ||
        filterVenue != nil ||
        filterTag != nil ||
        filterDateFrom != nil ||
        filterDateTo != nil
    }

    var activeFilterLabels: [String] {
        var labels: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        if let gameType = filterGameType {
            labels.append(gameType.rawValue)
        }
        if let variant = filterVariant {
            labels.append(variant)
        }
        if let stakes = filterStakes {
            labels.append(stakes)
        }
        if let venue = filterVenue {
            labels.append(venue)
        }
        if let tag = filterTag {
            labels.append("#\(tag)")
        }
        if let from = filterDateFrom, let to = filterDateTo {
            labels.append("\(formatter.string(from: from)) - \(formatter.string(from: to))")
        } else if let from = filterDateFrom {
            labels.append("From \(formatter.string(from: from))")
        } else if let to = filterDateTo {
            labels.append("Until \(formatter.string(from: to))")
        }
        return labels
    }

    var availableVariants: [String] {
        uniqueCaseInsensitiveStrings(sessions.map(\.displayVariant))
    }

    var availableStakes: [String] {
        uniqueCaseInsensitiveStrings(
            sessions.compactMap { session in
                let trimmed = session.stakes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    var availableVenues: [String] {
        uniqueCaseInsensitiveStrings(
            sessions.compactMap { session in
                VenueCleaner.clean(session.venue)
            }
        )
    }

    var venueSessionCounts: [(venue: String, sessions: Int)] {
        Dictionary(grouping: sessions) { session in
            VenueCleaner.clean(session.venue)
        }
        .compactMap { venue, sessions -> (venue: String, sessions: Int)? in
            guard let venue else { return nil }
            return (venue: venue, sessions: sessions.count)
        }
        .sorted { lhs, rhs in
            if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
            return lhs.venue.localizedCaseInsensitiveCompare(rhs.venue) == .orderedAscending
        }
    }

    func venueQuickOptions(using settings: AppSettings) -> [VenueQuickOption] {
        let manualVenues = AppSettings.normalizedVenueOptions(settings.pinnedVenueOptions)
        let hiddenKeys = Set(settings.hiddenVenueOptions.compactMap { VenueCleaner.key(for: $0) })
        let manualKeys = Set(manualVenues.compactMap { VenueCleaner.key(for: $0) })

        var options = manualVenues.map { venue in
            VenueQuickOption(venue: venue, source: .manual)
        }

        let automaticOptions = venueSessionCounts.compactMap { entry -> VenueQuickOption? in
            guard entry.sessions >= Self.automaticVenueQuickOptionThreshold else { return nil }
            guard let key = VenueCleaner.key(for: entry.venue) else { return nil }
            guard !hiddenKeys.contains(key), !manualKeys.contains(key) else { return nil }
            return VenueQuickOption(venue: entry.venue, source: .automatic(sessionCount: entry.sessions))
        }

        options.append(contentsOf: automaticOptions)
        return options
    }

    var availableTags: [String] {
        uniqueCaseInsensitiveStrings(sessions.flatMap(\.tags))
    }

    func clearFilters(includeSearch: Bool = false) {
        filterGameType = nil
        filterVariant = nil
        filterStakes = nil
        filterVenue = nil
        filterTag = nil
        filterDateFrom = nil
        filterDateTo = nil
        if includeSearch {
            searchText = ""
        }
    }
    
    // MARK: - Core Stats
    private func displayProfit(for session: PokerSession, settingsDefault: Bool) -> Double {
        session.displayProfit(deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsDefault))
    }

    private func isDisplayWin(_ session: PokerSession, settingsDefault: Bool) -> Bool {
        displayProfit(for: session, settingsDefault: settingsDefault) > 0.0001
    }

    private func isDisplayLoss(_ session: PokerSession, settingsDefault: Bool) -> Bool {
        displayProfit(for: session, settingsDefault: settingsDefault) < -0.0001
    }

    private func isDisplayBreakEven(_ session: PokerSession, settingsDefault: Bool) -> Bool {
        abs(displayProfit(for: session, settingsDefault: settingsDefault)) <= 0.0001
    }

    var totalProfit: Double { totalProfit(deductExpenses: true) }
    func totalProfit(deductExpenses: Bool) -> Double {
        totalProfit(settingsDefault: deductExpenses)
    }
    func totalProfit(settingsDefault: Bool) -> Double {
        filteredSessions.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
    }
    var totalExpenses: Double { filteredSessions.reduce(0) { $0 + $1.totalExpenses } }
    var totalSessions: Int { filteredSessions.count }
    var winCount: Int { winCount(settingsDefault: true) }
    func winCount(settingsDefault: Bool) -> Int {
        filteredSessions.filter { isDisplayWin($0, settingsDefault: settingsDefault) }.count
    }
    var lossCount: Int { lossCount(settingsDefault: true) }
    func lossCount(settingsDefault: Bool) -> Int {
        filteredSessions.filter { isDisplayLoss($0, settingsDefault: settingsDefault) }.count
    }
    var breakEvenCount: Int { breakEvenCount(settingsDefault: true) }
    func breakEvenCount(settingsDefault: Bool) -> Int {
        filteredSessions.filter { isDisplayBreakEven($0, settingsDefault: settingsDefault) }.count
    }
    var winRate: Double {
        winRate(settingsDefault: true)
    }
    func winRate(settingsDefault: Bool) -> Double {
        guard totalSessions > 0 else { return 0 }
        return Double(winCount(settingsDefault: settingsDefault)) / Double(totalSessions) * 100
    }
    
    // MARK: - Advanced Stats
    var totalHoursPlayed: Double {
        filteredSessions.compactMap { $0.hoursPlayed }.reduce(0, +)
    }
    var hourlyRate: Double? { hourlyRate(deductExpenses: true) }
    func hourlyRate(deductExpenses: Bool) -> Double? {
        hourlyRate(settingsDefault: deductExpenses)
    }
    func hourlyRate(settingsDefault: Bool) -> Double? {
        guard totalHoursPlayed > 0 else { return nil }
        return totalProfit(settingsDefault: settingsDefault) / totalHoursPlayed
    }
    var averageSession: Double { averageSession(deductExpenses: true) }
    func averageSession(deductExpenses: Bool) -> Double {
        averageSession(settingsDefault: deductExpenses)
    }
    func averageSession(settingsDefault: Bool) -> Double {
        guard totalSessions > 0 else { return 0 }
        return totalProfit(settingsDefault: settingsDefault) / Double(totalSessions)
    }
    var bestSession: PokerSession? { bestSession(deductExpenses: true) }
    func bestSession(deductExpenses: Bool) -> PokerSession? {
        bestSession(settingsDefault: deductExpenses)
    }
    func bestSession(settingsDefault: Bool) -> PokerSession? {
        filteredSessions.max(by: {
            displayProfit(for: $0, settingsDefault: settingsDefault) <
            displayProfit(for: $1, settingsDefault: settingsDefault)
        })
    }
    var worstSession: PokerSession? { worstSession(deductExpenses: true) }
    func worstSession(deductExpenses: Bool) -> PokerSession? {
        worstSession(settingsDefault: deductExpenses)
    }
    func worstSession(settingsDefault: Bool) -> PokerSession? {
        filteredSessions.min(by: {
            displayProfit(for: $0, settingsDefault: settingsDefault) <
            displayProfit(for: $1, settingsDefault: settingsDefault)
        })
    }
    
    // MARK: - Streaks
    var currentWinStreak: Int { currentWinStreak(settingsDefault: true) }
    func currentWinStreak(settingsDefault: Bool) -> Int {
        var streak = 0
        for session in filteredSessions {
            if isDisplayWin(session, settingsDefault: settingsDefault) { streak += 1 } else { break }
        }
        return streak
    }
    var currentLossStreak: Int { currentLossStreak(settingsDefault: true) }
    func currentLossStreak(settingsDefault: Bool) -> Int {
        var streak = 0
        for session in filteredSessions {
            if isDisplayLoss(session, settingsDefault: settingsDefault) { streak += 1 } else { break }
        }
        return streak
    }
    var longestWinStreak: Int { longestWinStreak(settingsDefault: true) }
    func longestWinStreak(settingsDefault: Bool) -> Int {
        var maxStreak = 0, current = 0
        for session in filteredSessions.reversed() {
            if isDisplayWin(session, settingsDefault: settingsDefault) { current += 1; maxStreak = max(maxStreak, current) }
            else { current = 0 }
        }
        return maxStreak
    }
    
    // MARK: - Chart Data
    var profitOverTime: [(Date, Double)] {
        profitOverTimeForDisplay(settingsDefault: true)
    }
    func profitOverTimeForDisplay(settingsDefault: Bool) -> [(Date, Double)] {
        var running: Double = 0
        return filteredDailyProfitForDisplay(settingsDefault: settingsDefault).map { day, profit in
            running += profit
            return (day, running)
        }
    }

    /// Peak-to-trough bankroll drawdown over time (0 = at peak, negative = below peak)
    var drawdownOverTime: [(Date, Double)] {
        drawdownOverTimeForDisplay(settingsDefault: true)
    }
    func drawdownOverTimeForDisplay(settingsDefault: Bool) -> [(Date, Double)] {
        var running: Double = 0
        var peak: Double = 0
        return filteredDailyProfitForDisplay(settingsDefault: settingsDefault).map { day, profit in
            running += profit
            peak = max(peak, running)
            return (day, running - peak)
        }
    }

    /// Weekday performance in locale order (includes empty weekdays with 0 sessions).
    /// average is average P/L per session for that weekday.
    func weekdayPerformance(settingsDefault: Bool = true) -> [(label: String, weekday: Int, average: Double, sessions: Int, total: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session in
            cal.component(.weekday, from: session.date) // 1...7
        }

        let rawSymbols = DateFormatter().shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let symbols = rawSymbols.count >= 7 ? rawSymbols : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let orderedWeekdays = (0..<7).map { offset in
            ((cal.firstWeekday - 1 + offset) % 7) + 1
        }

        return orderedWeekdays.map { weekday in
            let sessions = grouped[weekday] ?? []
            let total = sessions.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
            let count = sessions.count
            let avg = count > 0 ? total / Double(count) : 0
            let label = (1...7).contains(weekday) ? symbols[weekday - 1] : "?"
            return (
                label: label,
                weekday: weekday,
                average: avg,
                sessions: count,
                total: total
            )
        }
    }

    func hourlyRateBreakdown(for dimension: HourlyRateBreakdownDimension, settingsDefault: Bool = true) -> [HourlyRateBreakdownEntry] {
        let sessionsWithHours = filteredSessions.filter { session in
            guard let hours = session.hoursPlayed else { return false }
            return hours > 0
        }

        switch dimension {
        case .venue:
            return groupedHourlyRateBreakdown(from: sessionsWithHours, settingsDefault: settingsDefault) { session in
                VenueCleaner.clean(session.venue) ?? "Unknown Venue"
            }
        case .gameType:
            return groupedHourlyRateBreakdown(from: sessionsWithHours, settingsDefault: settingsDefault) { session in
                session.displayGameType
            }
        case .variant:
            return groupedHourlyRateBreakdown(from: sessionsWithHours, settingsDefault: settingsDefault) { session in
                PokerSession.abbreviation(for: session.displayVariant)
            }
        case .stakes:
            return groupedHourlyRateBreakdown(from: sessionsWithHours, settingsDefault: settingsDefault) { session in
                let trimmed = session.stakes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? "Unknown Stakes" : trimmed
            }
        case .weekday:
            let cal = Calendar.current
            let grouped = Dictionary(grouping: sessionsWithHours) { session in
                cal.component(.weekday, from: session.date)
            }

            let rawSymbols = DateFormatter().shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let symbols = rawSymbols.count >= 7 ? rawSymbols : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let orderedWeekdays = (0..<7).map { offset in
                ((cal.firstWeekday - 1 + offset) % 7) + 1
            }

            return orderedWeekdays.compactMap { weekday in
                let sessions = grouped[weekday] ?? []
                guard !sessions.isEmpty else { return nil }
                let label = (1...7).contains(weekday) ? symbols[weekday - 1] : "?"
                return makeHourlyRateBreakdownEntry(label: label, sessions: sessions, settingsDefault: settingsDefault)
            }
        }
    }

    func profitBreakdown(for dimension: ProfitBreakdownDimension, settingsDefault: Bool = true) -> [ProfitBreakdownEntry] {
        switch dimension {
        case .venue:
            return groupedProfitBreakdown(settingsDefault: settingsDefault) { session in
                VenueCleaner.clean(session.venue) ?? "Unknown Venue"
            }
        case .gameType:
            return groupedProfitBreakdown(settingsDefault: settingsDefault) { session in
                session.displayGameType
            }
        case .variant:
            return groupedProfitBreakdown(settingsDefault: settingsDefault) { session in
                PokerSession.abbreviation(for: session.displayVariant)
            }
        case .stakes:
            return groupedProfitBreakdown(settingsDefault: settingsDefault) { session in
                let trimmed = session.stakes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? "Unknown Stakes" : trimmed
            }
        case .weekday:
            return weekdayPerformance(settingsDefault: settingsDefault)
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
            .map { ($0.key, $0.value.count, $0.value.reduce(0) { $0 + $1.netAmount }) }
            .sorted { $0.1 > $1.1 }
    }
    
    var monthlyProfit: [(String, Double)] {
        monthlyProfitForDisplay(settingsDefault: true)
    }
    func monthlyProfitForDisplay(settingsDefault: Bool) -> [(String, Double)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.date)) ?? session.date
        }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }) }
            .sorted { $0.0 < $1.0 }
            .map { (formatter.string(from: $0.0), $0.1) }
    }
    
    /// Monthly profit with Date for chart domain (month start dates)
    var monthlyProfitWithDates: [(Date, Double)] {
        monthlyProfitWithDatesForDisplay(settingsDefault: true)
    }
    func monthlyProfitWithDatesForDisplay(settingsDefault: Bool) -> [(Date, Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.date)) ?? session.date
        }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }) }
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
        guard !filteredSessions.isEmpty,
              let minSession = filteredSessions.min(by: { $0.date < $1.date }),
              let maxSession = filteredSessions.max(by: { $0.date < $1.date }) else { return nil }
        let calendar = Calendar.current
        let first = minSession.date
        let last = maxSession.date
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
        guard !filteredSessions.isEmpty,
              let minSession = filteredSessions.min(by: { $0.date < $1.date }),
              let maxSession = filteredSessions.max(by: { $0.date < $1.date }) else { return nil }
        let calendar = Calendar.current
        let first = minSession.date
        let last = maxSession.date
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
        guard !sessions.isEmpty,
              let minSession = sessions.min(by: { $0.date < $1.date }),
              let maxSession = sessions.max(by: { $0.date < $1.date }) else { return nil }
        let first = minSession.date
        let last = maxSession.date
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (calendar.startOfDay(for: first), endOfDay(for: max(last, today), using: calendar))
    }
    
    var thisMonthProfit: Double {
        thisMonthProfitForDisplay(settingsDefault: true)
    }
    func thisMonthProfitForDisplay(settingsDefault: Bool) -> Double {
        let calendar = Calendar.current
        let now = Date()
        return filteredSessions
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
    }
    
    /// Sessions on a given calendar day.
    func sessions(on date: Date, respectingFilters: Bool = false) -> [PokerSession] {
        let source = respectingFilters ? filteredSessions : sessions
        return source.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted(by: isSessionEarlier(lhs:rhs:))
    }
    
    /// Total profit for a given calendar day
    func dailyProfit(on date: Date, respectingFilters: Bool = false, settingsDefault: Bool = true) -> Double {
        sessions(on: date, respectingFilters: respectingFilters).reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
    }
    
    /// Total profit for a given month
    func monthlyProfit(for monthStart: Date, respectingFilters: Bool = false, settingsDefault: Bool = true) -> Double {
        let cal = Calendar.current
        let source = respectingFilters ? filteredSessions : sessions
        return source
            .filter { cal.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
            .reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
    }
    
    // MARK: - Session Numbering (dynamic: earliest = #1, latest = #N)
    
    /// Sessions sorted earliest to latest (used for display numbers; uses all sessions for stable numbering)
    var sessionsByDateAscending: [PokerSession] {
        sortedSessionsAscending(sessions)
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
            let previous = sessions[i]
            var updated = sessions
            updated[i] = session
            let sorted = sortedSessions(updated)
            let removedImageIDs = Set(previous.imageIds).subtracting(session.imageIds)
            deleteImagesNoLongerReferenced(removedImageIDs, in: sorted)
            sessions = sorted
        }
    }

    func addAttachedHand(_ hand: PokerSession.AttachedHand, toSessionID id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = sessions
        updated[i].attachedHands.append(hand)
        sessions = sortedSessions(updated)
    }
    
    func deleteSession(_ session: PokerSession) {
        let remainingSessions = sessions.filter { $0.id != session.id }
        deleteImagesNoLongerReferenced(Set(session.imageIds), in: remainingSessions)
        sessions = remainingSessions
    }

    private func groupedProfitBreakdown(settingsDefault: Bool = true, _ labelForSession: (PokerSession) -> String) -> [ProfitBreakdownEntry] {
        Dictionary(grouping: filteredSessions, by: labelForSession)
            .map { label, sessions in
                let profit = sessions.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
                return ProfitBreakdownEntry(
                    label: label,
                    profit: profit,
                    sessions: sessions.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.profit != rhs.profit { return lhs.profit > rhs.profit }
                if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
                return lhs.label < rhs.label
            }
    }

    private func groupedHourlyRateBreakdown(
        from sessions: [PokerSession],
        settingsDefault: Bool = true,
        _ labelForSession: (PokerSession) -> String
    ) -> [HourlyRateBreakdownEntry] {
        Dictionary(grouping: sessions, by: labelForSession)
            .map { label, sessions in
                makeHourlyRateBreakdownEntry(label: label, sessions: sessions, settingsDefault: settingsDefault)
            }
            .sorted { lhs, rhs in
                if lhs.hourlyRate != rhs.hourlyRate { return lhs.hourlyRate > rhs.hourlyRate }
                if lhs.totalHours != rhs.totalHours { return lhs.totalHours > rhs.totalHours }
                if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
                return lhs.label < rhs.label
            }
    }

    private func makeHourlyRateBreakdownEntry(
        label: String,
        sessions: [PokerSession],
        settingsDefault: Bool = true
    ) -> HourlyRateBreakdownEntry {
        let totalProfit = sessions.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) }
        let totalHours = sessions.compactMap(\.hoursPlayed).reduce(0, +)
        return HourlyRateBreakdownEntry(
            label: label,
            totalProfit: totalProfit,
            totalHours: totalHours,
            sessions: sessions.count
        )
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

        var csv = "Date,Game Format,Variant,Gross Amount,Total Expenses,Rake,Tips,Food,Travel,Fees,Net Amount,Hours,Stakes,Venue,Tags,Notes\n"
        for s in sortedSessionsDescending(sessions) {
            let date = ISO8601DateFormatter().string(from: s.date)
            let grossAmount = PokerSession.formatCurrency(s.amount, currency: currency)
            let totalExpenses = PokerSession.formatCurrency(s.totalExpenses, currency: currency)
            let rake = s.rake.map { PokerSession.formatCurrency($0, currency: currency) } ?? ""
            let tips = s.tips.map { PokerSession.formatCurrency($0, currency: currency) } ?? ""
            let food = s.food.map { PokerSession.formatCurrency($0, currency: currency) } ?? ""
            let travel = s.travel.map { PokerSession.formatCurrency($0, currency: currency) } ?? ""
            let fees = s.fees.map { PokerSession.formatCurrency($0, currency: currency) } ?? ""
            let netAmount = PokerSession.formatCurrency(s.netAmount, currency: currency)
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
                escapeCSV(s.displayGameType),
                escapeCSV(variant),
                escapeCSV(grossAmount),
                escapeCSV(totalExpenses),
                escapeCSV(rake),
                escapeCSV(tips),
                escapeCSV(food),
                escapeCSV(travel),
                escapeCSV(fees),
                escapeCSV(netAmount),
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

    func syncCloudBackupNow() {
        updateCloudBackupStatus(state: .syncing)
        guard isICloudSignedIn else {
            refreshCloudBackupStatus()
            return
        }

        cloudStore.synchronize()
        if !syncFromCloudIfNewer() {
            pushCurrentSessionsToCloud()
        }
        refreshCloudBackupStatus()
    }

    func refreshCloudBackupStatusForDisplay() {
        refreshCloudBackupStatus()
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

        pushSessionsToCloud(encoded: encoded, updatedAt: updatedAt)
        refreshCloudBackupStatus(encodedSessions: encoded)
    }

    @discardableResult
    private func syncFromCloudIfNewer() -> Bool {
        let cloudUpdatedAt = cloudStore.double(forKey: cloudSaveUpdatedAtKey)
        let localUpdatedAt = UserDefaults.standard.double(forKey: saveUpdatedAtKey)
        guard cloudUpdatedAt > localUpdatedAt else { return false }
        guard let cloudData = cloudStore.data(forKey: cloudSaveKey),
              let decoded = decodeSessions(from: cloudData) else { return false }

        isApplyingCloudSync = true
        cloudSyncUpdatedAt = cloudUpdatedAt
        replaceSessionsWithCleanup(decoded)
        cloudSyncUpdatedAt = nil
        isApplyingCloudSync = false
        recordSuccessfulCloudSync()
        refreshCloudBackupStatus(encodedSessions: cloudData)
        return true
    }

    private func decodeSessions(from data: Data) -> [PokerSession]? {
        try? JSONDecoder().decode([PokerSession].self, from: data)
    }

    private var isICloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func pushCurrentSessionsToCloud() {
        guard let encoded = try? JSONEncoder().encode(sessions) else {
            refreshCloudBackupStatus()
            return
        }
        let localUpdatedAt = UserDefaults.standard.double(forKey: saveUpdatedAtKey)
        let updatedAt = localUpdatedAt > 0 ? localUpdatedAt : Date().timeIntervalSince1970
        pushSessionsToCloud(encoded: encoded, updatedAt: updatedAt)
    }

    private func pushSessionsToCloud(encoded: Data, updatedAt: TimeInterval) {
        guard isICloudSignedIn else { return }
        guard encoded.count <= Self.cloudBackupPayloadLimitBytes else { return }

        cloudStore.set(encoded, forKey: cloudSaveKey)
        cloudStore.set(updatedAt, forKey: cloudSaveUpdatedAtKey)
        cloudStore.synchronize()
        recordSuccessfulCloudSync()
    }

    private func recordSuccessfulCloudSync() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCloudSyncAtKey)
    }

    private func refreshCloudBackupStatus(encodedSessions: Data? = nil) {
        let encoded = encodedSessions ?? (try? JSONEncoder().encode(sessions))
        let payloadBytes = encoded?.count ?? 0
        let lastSyncedAt = lastCloudSyncDate()

        if !isICloudSignedIn {
            cloudBackupStatus = CloudBackupStatus(
                state: .notSignedIn,
                lastSyncedAt: lastSyncedAt,
                payloadBytes: payloadBytes,
                payloadLimitBytes: Self.cloudBackupPayloadLimitBytes
            )
            return
        }

        if payloadBytes > Self.cloudBackupPayloadLimitBytes {
            cloudBackupStatus = CloudBackupStatus(
                state: .backupTooLarge,
                lastSyncedAt: lastSyncedAt,
                payloadBytes: payloadBytes,
                payloadLimitBytes: Self.cloudBackupPayloadLimitBytes
            )
            return
        }

        cloudBackupStatus = CloudBackupStatus(
            state: lastSyncedAt == nil ? .neverSynced : .synced,
            lastSyncedAt: lastSyncedAt,
            payloadBytes: payloadBytes,
            payloadLimitBytes: Self.cloudBackupPayloadLimitBytes
        )
    }

    private func updateCloudBackupStatus(state: CloudBackupState) {
        let payloadBytes = (try? JSONEncoder().encode(sessions))?.count ?? cloudBackupStatus.payloadBytes
        cloudBackupStatus = CloudBackupStatus(
            state: state,
            lastSyncedAt: cloudBackupStatus.lastSyncedAt,
            payloadBytes: payloadBytes,
            payloadLimitBytes: Self.cloudBackupPayloadLimitBytes
        )
    }

    private func lastCloudSyncDate() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastCloudSyncAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func replaceSessionsWithCleanup(_ restoredSessions: [PokerSession]) {
        let currentImageIDs = Set(sessions.flatMap(\.imageIds))
        let restoredImageIDs = Set(restoredSessions.flatMap(\.imageIds))
        let sortedRestoredSessions = sortedSessions(restoredSessions)
        deleteImagesNoLongerReferenced(currentImageIDs.subtracting(restoredImageIDs), in: sortedRestoredSessions)
        sessions = sortedRestoredSessions
    }

    private var filteredDailyProfit: [(Date, Double)] {
        filteredDailyProfitForDisplay(settingsDefault: true)
    }
    private func filteredDailyProfitForDisplay(settingsDefault: Bool) -> [(Date, Double)] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.date)
        }
        .map { day, sessions in
            (day, sessions.reduce(0) { $0 + displayProfit(for: $1, settingsDefault: settingsDefault) })
        }
        .sorted { $0.0 < $1.0 }
    }

    private func endOfDay(for date: Date, using calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return nextDay.addingTimeInterval(-1)
    }

    private func sortedSessions(_ source: [PokerSession]) -> [PokerSession] {
        sortedSessionsDescending(source.map(normalizedSession(_:)))
    }

    private func sortedSessionsDescending(_ source: [PokerSession]) -> [PokerSession] {
        source.sorted(by: isSessionLater(lhs:rhs:))
    }

    private func sortedSessionsAscending(_ source: [PokerSession]) -> [PokerSession] {
        source.sorted(by: isSessionEarlier(lhs:rhs:))
    }

    private func isSessionLater(lhs: PokerSession, rhs: PokerSession) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func isSessionEarlier(lhs: PokerSession, rhs: PokerSession) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func normalizedSession(_ session: PokerSession) -> PokerSession {
        var normalized = session
        normalized.rake = normalizedExpense(normalized.rake)
        normalized.tips = normalizedExpense(normalized.tips)
        normalized.food = normalizedExpense(normalized.food)
        normalized.travel = normalizedExpense(normalized.travel)
        normalized.fees = normalizedExpense(normalized.fees)
        normalized.hoursPlayed = normalizedDuration(normalized.hoursPlayed)
        normalized.variant = normalizedVariant(normalized.variant)
        normalized.stakes = normalizedStakes(normalized.stakes)
        normalized.venue = VenueCleaner.clean(normalized.venue)
        normalized.handNotes = normalizedOptionalText(normalized.handNotes)
        normalized.notes = normalized.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.tags = normalizedTags(normalized.tags)
        normalized.tournamentPosition = normalizedPositiveInt(normalized.tournamentPosition)
        normalized.buyins = normalizedBuyins(normalized.buyins)

        // Legacy PLO sessions should be stored as cash sessions with a PLO variant.
        if normalized.gameType == .plo {
            normalized.gameType = .cash
            if normalized.variant == nil {
                normalized.variant = PokerVariant.plo.rawValue
            }
        }

        if let calculated = PokerSession.calculatedHours(from: normalized.startTime, to: normalized.endTime),
           normalized.hoursPlayed == nil {
            normalized.hoursPlayed = calculated
        }

        if (normalized.gameType == .tournament || normalized.gameType == .sitAndGo),
           let buyIn = normalized.buyIn, let cashOut = normalized.cashOut {
            let effectiveBuyins = max(1, normalized.buyins ?? 1)
            normalized.amount = cashOut - (buyIn * Double(effectiveBuyins))
        }
        return normalized
    }

    private func uniqueCaseInsensitiveStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            uniqueValues.append(trimmed)
        }

        return uniqueValues.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func normalizedExpense(_ value: Double?) -> Double? {
        guard let value else { return nil }
        let normalized = abs(value)
        return normalized > 0.0001 ? normalized : nil
    }

    private func normalizedDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value > 0.0001 ? value : nil
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedStakes(_ value: String?) -> String? {
        guard let trimmed = normalizedOptionalText(value) else { return nil }

        let parts = trimmed
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 {
            guard stakeComponentHasValue(parts[0]), stakeComponentHasValue(parts[1]) else { return nil }
        } else {
            guard stakeComponentHasValue(parts[0]), stakeComponentHasValue(parts[2]) else { return nil }
            // Allow empty middle (e.g. "1//5" for small/straddle only)
        }
        return trimmed
    }

    private func normalizedVariant(_ value: String?) -> String? {
        guard let trimmed = normalizedOptionalText(value) else { return nil }
        if let exact = PokerVariant.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.rawValue
        }
        return trimmed
    }

    private func stakeComponentHasValue(_ value: String) -> Bool {
        var cleaned = value
        for symbol in Self.supportedCurrencySymbolsForStakes {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "", options: [.caseInsensitive])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for rawTag in tags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = SessionTag.allCases.first {
                $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
            }?.rawValue ?? trimmed
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    private func normalizedPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func normalizedNonNegativeInt(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value == 0 ? nil : value
    }

    private func normalizedBuyins(_ value: Int?) -> Int? {
        guard let value, value >= 1 else { return nil }
        return min(12, value)
    }

    private func deleteImagesNoLongerReferenced(_ candidateImageIDs: Set<String>, in source: [PokerSession]) {
        guard !candidateImageIDs.isEmpty else { return }
        let referencedImageIDs = Set(source.flatMap(\.imageIds))
        let orphanedImageIDs = candidateImageIDs.subtracting(referencedImageIDs)
        guard !orphanedImageIDs.isEmpty else { return }
        SessionImageStore.delete(imageIds: Array(orphanedImageIDs))
    }
}
