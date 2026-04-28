//
//  WidgetSnapshotStore.swift
//  PokerTrackerIOS
//

import Foundation

#if !WIDGET_EXTENSION
import WidgetKit
#endif

struct PokerWidgetSnapshot: Codable, Equatable {
    struct LatestSession: Codable, Equatable {
        let title: String
        let subtitle: String
        let amountText: String
        let isProfit: Bool
        let dateText: String
    }

    struct CalendarDay: Codable, Equatable, Identifiable {
        let id: Int
        let dayText: String
        let amountText: String?
        let isProfit: Bool
        let isToday: Bool
        let hasSession: Bool
        let isInMonth: Bool
    }

    let updatedAt: Date
    let bankrollText: String
    let profitText: String
    let isProfit: Bool
    let sessionCountText: String
    let winRateText: String
    let hourlyRateText: String?
    let monthProfitText: String
    let isMonthProfit: Bool
    let monthSessionCountText: String
    let latestSession: LatestSession?
    let calendarMonthTitle: String
    let calendarWeekdaySymbols: [String]
    let calendarDays: [CalendarDay]

    static let placeholder = PokerWidgetSnapshot(
        updatedAt: Date(),
        bankrollText: "$4,280",
        profitText: "+$1,120",
        isProfit: true,
        sessionCountText: "18",
        winRateText: "61%",
        hourlyRateText: "$42/hr",
        monthProfitText: "+$640",
        isMonthProfit: true,
        monthSessionCountText: "5",
        latestSession: LatestSession(
            title: "Latest Session",
            subtitle: "Bellagio - $2/$5",
            amountText: "+$320",
            isProfit: true,
            dateText: "Today"
        ),
        calendarMonthTitle: placeholderMonthTitle,
        calendarWeekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
        calendarDays: placeholderCalendarDays
    )

    static let empty = PokerWidgetSnapshot(
        updatedAt: Date(),
        bankrollText: "$0",
        profitText: "$0",
        isProfit: true,
        sessionCountText: "0",
        winRateText: "0%",
        hourlyRateText: nil,
        monthProfitText: "$0",
        isMonthProfit: true,
        monthSessionCountText: "0",
        latestSession: nil,
        calendarMonthTitle: placeholderMonthTitle,
        calendarWeekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
        calendarDays: emptyCalendarDays
    )

    private static var placeholderMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private static var emptyCalendarDays: [CalendarDay] {
        calendarDays(dailyValues: [:], activeDays: [])
    }

    private static var placeholderCalendarDays: [CalendarDay] {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: Date())
        let sampleValues: [Int: (text: String, isProfit: Bool)] = [
            max(1, today - 6): ("+$90", true),
            max(1, today - 2): ("-$45", false),
            today: ("+$320", true)
        ]
        return calendarDays(dailyValues: sampleValues, activeDays: Set(sampleValues.keys))
    }

    private static func calendarDays(
        dailyValues: [Int: (text: String, isProfit: Bool)],
        activeDays: Set<Int>
    ) -> [CalendarDay] {
        let calendar = Calendar.current
        let today = Date()
        let components = calendar.dateComponents([.year, .month], from: today)
        guard let monthStart = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalCells = 42

        return (0..<totalCells).map { index in
            let dayNumber = index - leadingBlanks + 1
            let isInMonth = dayRange.contains(dayNumber)
            let value = dailyValues[dayNumber]
            return CalendarDay(
                id: index,
                dayText: isInMonth ? "\(dayNumber)" : "",
                amountText: isInMonth ? value?.text : nil,
                isProfit: value?.isProfit ?? true,
                isToday: isInMonth && dayNumber == calendar.component(.day, from: today),
                hasSession: isInMonth && activeDays.contains(dayNumber),
                isInMonth: isInMonth
            )
        }
    }
}

enum PokerWidgetRoute: String {
    case odds
    case aiLog
    case manualLog
    case calendar
}

enum PokerWidgetSnapshotStore {
    static let appGroupID = "group.com.jakealessi.PokerTrackerIOS"
    private static let snapshotKey = "poker_widget_snapshot"

    static func load() -> PokerWidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(PokerWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

#if !WIDGET_EXTENSION
    static func refresh(sessions: [PokerSession], settings: AppSettings) {
        let snapshot = makeSnapshot(sessions: sessions, settings: settings)
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func makeSnapshot(sessions: [PokerSession], settings: AppSettings) -> PokerWidgetSnapshot {
        let settingsDefault = settings.deductExpensesFromProfit
        let sessionProfits = sessions.map { session in
            session.displayProfit(
                deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsDefault)
            )
        }
        let totalProfit = sessionProfits.reduce(0, +)
        let bankroll = settings.startingBankroll + totalProfit
        let winCount = sessionProfits.filter { $0 > 0.0001 }.count
        let totalHours = sessions.compactMap(\.hoursPlayed).reduce(0, +)
        let hourlyRate = settings.showHourlyRate && totalHours > 0 ? totalProfit / totalHours : nil
        let monthSessions = sessions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
        let monthProfit = monthSessions.reduce(0) { total, session in
            total + session.displayProfit(
                deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsDefault)
            )
        }

        return PokerWidgetSnapshot(
            updatedAt: Date(),
            bankrollText: displayAmount(bankroll, settings: settings, includePositiveSign: false),
            profitText: displayAmount(totalProfit, settings: settings),
            isProfit: totalProfit >= 0,
            sessionCountText: "\(sessions.count)",
            winRateText: winRateText(wins: winCount, sessions: sessions.count),
            hourlyRateText: hourlyRate.map { "\(displayAmount($0, settings: settings))/hr" },
            monthProfitText: displayAmount(monthProfit, settings: settings),
            isMonthProfit: monthProfit >= 0,
            monthSessionCountText: "\(monthSessions.count)",
            latestSession: latestSession(from: sessions, settings: settings, settingsDefault: settingsDefault),
            calendarMonthTitle: calendarMonthTitle(),
            calendarWeekdaySymbols: weekdaySymbols(),
            calendarDays: calendarDays(from: sessions, settings: settings, settingsDefault: settingsDefault)
        )
    }

    private static func latestSession(
        from sessions: [PokerSession],
        settings: AppSettings,
        settingsDefault: Bool
    ) -> PokerWidgetSnapshot.LatestSession? {
        guard let session = sessions.max(by: {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }) else { return nil }
        let amount = session.displayProfit(
            deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsDefault)
        )
        let venue = VenueCleaner.clean(session.venue)
        let stakes = session.stakes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = [venue, stakes]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")

        return PokerWidgetSnapshot.LatestSession(
            title: session.displayVariantAbbreviation,
            subtitle: subtitle.isEmpty ? session.displayGameType : subtitle,
            amountText: displayAmount(amount, settings: settings),
            isProfit: amount >= 0,
            dateText: relativeDateText(for: session.date)
        )
    }

    private static func winRateText(wins: Int, sessions: Int) -> String {
        guard sessions > 0 else { return "0%" }
        let winRate = Double(wins) / Double(sessions) * 100
        return "\(Int(winRate.rounded()))%"
    }

    private static func displayAmount(
        _ value: Double,
        settings: AppSettings,
        includePositiveSign: Bool = true
    ) -> String {
        settings.displayAmount(value, compact: settings.useCompactCurrency, includePositiveSign: includePositiveSign)
    }

    private static func relativeDateText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateStyle = calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? .medium : .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func calendarMonthTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private static func weekdaySymbols() -> [String] {
        let calendar = Calendar.current
        let symbols = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { offset in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return symbols.indices.contains(index) ? symbols[index] : "?"
        }
    }

    private static func calendarDays(
        from sessions: [PokerSession],
        settings: AppSettings,
        settingsDefault: Bool
    ) -> [PokerWidgetSnapshot.CalendarDay] {
        let calendar = Calendar.current
        let today = Date()
        let components = calendar.dateComponents([.year, .month], from: today)
        guard let monthStart = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let monthSessions = sessions.filter { calendar.isDate($0.date, equalTo: today, toGranularity: .month) }
        let groupedByDay = Dictionary(grouping: monthSessions) { session in
            calendar.component(.day, from: session.date)
        }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalCells = 42
        let todayDay = calendar.component(.day, from: today)

        return (0..<totalCells).map { index in
            let dayNumber = index - leadingBlanks + 1
            let isInMonth = dayRange.contains(dayNumber)
            let daySessions = isInMonth ? groupedByDay[dayNumber] ?? [] : []
            let dailyProfit = daySessions.reduce(0) { total, session in
                total + session.displayProfit(
                    deductExpenses: session.effectiveDeductExpenses(settingsDefault: settingsDefault)
                )
            }

            return PokerWidgetSnapshot.CalendarDay(
                id: index,
                dayText: isInMonth ? "\(dayNumber)" : "",
                amountText: isInMonth && !daySessions.isEmpty
                    ? displayAmount(dailyProfit, settings: settings, includePositiveSign: dailyProfit > 0)
                    : nil,
                isProfit: dailyProfit >= 0,
                isToday: isInMonth && dayNumber == todayDay,
                hasSession: !daySessions.isEmpty,
                isInMonth: isInMonth
            )
        }
    }
#endif
}

enum PokerWidgetRouteStore {
    private static let pendingRouteKey = "poker_widget_pending_route"

    static func setPendingRoute(_ route: PokerWidgetRoute) {
        defaults.set(route.rawValue, forKey: pendingRouteKey)
        defaults.synchronize()
    }

#if !WIDGET_EXTENSION
    static func consumePendingRoute() -> PokerWidgetRoute? {
        guard let rawValue = defaults.string(forKey: pendingRouteKey) else {
            return nil
        }
        guard let route = PokerWidgetRoute(rawValue: rawValue) else {
            defaults.removeObject(forKey: pendingRouteKey)
            defaults.synchronize()
            return nil
        }
        defaults.removeObject(forKey: pendingRouteKey)
        defaults.synchronize()
        return route
    }
#endif

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PokerWidgetSnapshotStore.appGroupID) ?? .standard
    }
}
