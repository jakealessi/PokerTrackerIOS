//
//  PokerBankrollWidgets.swift
//  PokerTrackerWidgets
//

import SwiftUI
import AppIntents
import WidgetKit

struct PokerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PokerWidgetSnapshot
}

struct PokerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PokerWidgetEntry {
        PokerWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PokerWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? PokerWidgetSnapshot.placeholder : PokerWidgetSnapshotStore.load()
        completion(PokerWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PokerWidgetEntry>) -> Void) {
        let snapshot = context.isPreview ? PokerWidgetSnapshot.placeholder : PokerWidgetSnapshotStore.load()
        let entry = PokerWidgetEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

@main
struct PokerBankrollWidgetBundle: WidgetBundle {
    var body: some Widget {
        BankrollSummaryWidget()
        MonthlyProfitWidget()
        LatestSessionWidget()
        CalendarPerformanceWidget()
        PokerShortcutWidget()
    }
}

struct BankrollSummaryWidget: Widget {
    let kind = "BankrollSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            BankrollSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Bankroll")
        .description("See bankroll, profit, sessions, and win rate.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonthlyProfitWidget: Widget {
    let kind = "MonthlyProfitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            MonthlyProfitWidgetView(entry: entry)
        }
        .configurationDisplayName("This Month")
        .description("Track this month's poker performance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LatestSessionWidget: Widget {
    let kind = "LatestSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            LatestSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Latest Session")
        .description("Show your most recent recorded poker session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CalendarPerformanceWidget: Widget {
    let kind = "CalendarPerformanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            CalendarPerformanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Calendar")
        .description("See this month's session results by day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PokerShortcutWidget: Widget {
    let kind = "PokerShortcutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            PokerShortcutWidgetView(entry: entry)
        }
        .configurationDisplayName("Poker Shortcuts")
        .description("Jump to odds, AI logging, or manual session logging.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BankrollSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
                WidgetHeader(title: "Bankroll", subtitle: "All time")

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.snapshot.bankrollText)
                        .font(.system(size: family == .systemSmall ? 28 : 34, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.snapshot.isProfit ? WidgetPalette.win : WidgetPalette.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(entry.snapshot.profitText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.snapshot.isProfit ? WidgetPalette.win : WidgetPalette.loss)
                        .lineLimit(1)
                }

                if family == .systemMedium {
                    HStack(spacing: 10) {
                        StatPill(label: "Sessions", value: entry.snapshot.sessionCountText)
                        StatPill(label: "Win Rate", value: entry.snapshot.winRateText)
                        if let hourlyRateText = entry.snapshot.hourlyRateText {
                            StatPill(label: "Hourly", value: hourlyRateText)
                        }
                    }
                } else {
                    HStack {
                        CompactStat(label: "Sessions", value: entry.snapshot.sessionCountText)
                        Spacer()
                        CompactStat(label: "Win", value: entry.snapshot.winRateText)
                    }
                }
            }
        }
    }
}

private struct MonthlyProfitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "calendar") {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 14) {
                WidgetHeader(title: "This Month", subtitle: "Performance")

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.monthProfitText)
                        .font(.system(size: family == .systemSmall ? 31 : 38, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.snapshot.isMonthProfit ? WidgetPalette.win : WidgetPalette.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text("\(entry.snapshot.monthSessionCountText) sessions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if family == .systemMedium {
                    HStack(spacing: 10) {
                        StatPill(label: "All Profit", value: entry.snapshot.profitText)
                        StatPill(label: "Win Rate", value: entry.snapshot.winRateText)
                        StatPill(label: "Total", value: entry.snapshot.sessionCountText)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct LatestSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "clock.arrow.circlepath") {
            if let latestSession = entry.snapshot.latestSession {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 12) {
                    WidgetHeader(title: "Latest", subtitle: latestSession.dateText)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(latestSession.amountText)
                            .font(.system(size: family == .systemSmall ? 31 : 38, weight: .bold, design: .rounded))
                            .foregroundStyle(latestSession.isProfit ? WidgetPalette.win : WidgetPalette.loss)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text(latestSession.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(latestSession.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(family == .systemSmall ? 1 : 2)
                    }

                    if family == .systemMedium {
                        Spacer(minLength: 0)
                        Text("Bankroll \(entry.snapshot.bankrollText)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                EmptyLatestSessionContent()
            }
        }
    }
}

private struct CalendarPerformanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "calendar") {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
                HStack(alignment: .firstTextBaseline) {
                    WidgetHeader(title: "Calendar", subtitle: entry.snapshot.calendarMonthTitle)
                    Spacer(minLength: 0)
                    Text(entry.snapshot.monthProfitText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.snapshot.isMonthProfit ? WidgetPalette.win : WidgetPalette.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 3) {
                    ForEach(Array(entry.snapshot.calendarWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(entry.snapshot.calendarDays) { day in
                        CalendarWidgetDayCell(
                            day: day,
                            showAmount: family == .systemMedium
                        )
                    }
                }

                if family == .systemMedium {
                    Text("\(entry.snapshot.monthSessionCountText) sessions this month")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct PokerShortcutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 11) {
                WidgetHeader(title: "Shortcuts", subtitle: "Quick actions")

                if family == .systemSmall {
                    VStack(spacing: 7) {
                        ShortcutButton(
                            destination: .odds,
                            icon: "percent",
                            title: "Odds",
                            subtitle: "Calculate"
                        )
                        ShortcutButton(
                            destination: .aiLog,
                            icon: "sparkles",
                            title: "AI Log",
                            subtitle: "Chat"
                        )
                        ShortcutButton(
                            destination: .manualLog,
                            icon: "plus.circle.fill",
                            title: "Manual",
                            subtitle: "Session"
                        )
                    }
                } else {
                    HStack(spacing: 9) {
                        ShortcutButton(
                            destination: .odds,
                            icon: "percent",
                            title: "Calculate Odds",
                            subtitle: "Equity"
                        )
                        ShortcutButton(
                            destination: .aiLog,
                            icon: "sparkles",
                            title: "AI Log",
                            subtitle: "Session"
                        )
                        ShortcutButton(
                            destination: .manualLog,
                            icon: "plus.circle.fill",
                            title: "Manual Log",
                            subtitle: "Session"
                        )
                    }
                }
            }
        }
    }
}

private struct WidgetShell<Content: View>: View {
    let snapshot: PokerWidgetSnapshot
    let icon: String
    let content: Content

    init(snapshot: PokerWidgetSnapshot, icon: String, @ViewBuilder content: () -> Content) {
        self.snapshot = snapshot
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.accent.opacity(0.85))
                .padding(6)
                .background(Circle().fill(WidgetPalette.accent.opacity(0.12)))
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    WidgetPalette.accent.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct CalendarWidgetDayCell: View {
    let day: PokerWidgetSnapshot.CalendarDay
    let showAmount: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(day.dayText)
                .font(.system(size: 9, weight: day.isToday ? .bold : .semibold, design: .rounded))
                .foregroundStyle(day.isInMonth ? Color.primary : Color.clear)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if showAmount, let amountText = day.amountText {
                Text(amountText)
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(day.isProfit ? WidgetPalette.win : WidgetPalette.loss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            } else {
                Circle()
                    .fill(day.hasSession ? (day.isProfit ? WidgetPalette.win : WidgetPalette.loss) : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: showAmount ? 24 : 15)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(dayBackground)
        )
    }

    private var dayBackground: Color {
        if day.isToday {
            return WidgetPalette.accent.opacity(0.16)
        }
        if day.hasSession {
            return (day.isProfit ? WidgetPalette.win : WidgetPalette.loss).opacity(0.10)
        }
        return Color(UIColor.secondarySystemBackground).opacity(0.45)
    }
}

private struct ShortcutButton: View {
    let destination: PokerShortcutDestination
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Button(intent: OpenPokerShortcutIntent(destination: destination)) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WidgetPalette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.82))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WidgetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct CompactStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.82))
        )
    }
}

private struct EmptyLatestSessionContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Latest", subtitle: "No sessions")
            Spacer(minLength: 0)
            Text("No poker sessions yet.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Add one in Poker Bankroll AI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private enum WidgetPalette {
    static let accent = Color(red: 0.10, green: 0.35, blue: 0.95)
    static let win = Color(red: 0.05, green: 0.55, blue: 0.28)
    static let loss = Color(red: 0.86, green: 0.19, blue: 0.18)
}

enum PokerShortcutDestination: String, AppEnum {
    case odds
    case aiLog
    case manualLog

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Poker Shortcut")
    static var caseDisplayRepresentations: [PokerShortcutDestination: DisplayRepresentation] = [
        .odds: "Calculate Odds",
        .aiLog: "AI Log Session",
        .manualLog: "Manual Log Session"
    ]

    var route: PokerWidgetRoute {
        switch self {
        case .odds: return .odds
        case .aiLog: return .aiLog
        case .manualLog: return .manualLog
        }
    }
}

struct OpenPokerShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Poker Shortcut"
    static var description = IntentDescription("Opens Poker Bankroll AI to a selected tool.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: PokerShortcutDestination

    init() {
        destination = .aiLog
    }

    init(destination: PokerShortcutDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        PokerWidgetRouteStore.setPendingRoute(destination.route)
        return .result()
    }
}
