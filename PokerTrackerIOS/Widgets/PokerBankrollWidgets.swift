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
        let nextRefresh = WidgetTimelineRefreshPolicy.nextRefreshDate(from: Date())
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private enum WidgetTimelineRefreshPolicy {
    static func nextRefreshDate(from date: Date) -> Date {
        let calendar = Calendar.current
        let regularRefresh = calendar.date(byAdding: .minute, value: 15, to: date) ?? date.addingTimeInterval(900)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
              let nextMidnight = calendar.dateInterval(of: .day, for: tomorrow)?.start else {
            return regularRefresh
        }
        return min(regularRefresh, nextMidnight.addingTimeInterval(2))
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
        LogSessionLockScreenWidget()
        AILogLockScreenWidget()
        OddsLockScreenWidget()
    }
}

struct BankrollSummaryWidget: Widget {
    let kind = "BankrollSummaryStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            BankrollSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Bankroll")
        .description("See bankroll, profit, sessions, and win rate.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall])
    }
}

struct MonthlyProfitWidget: Widget {
    let kind = "MonthlyPerformanceStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { entry in
            MonthlyProfitWidgetView(entry: entry)
        }
        .configurationDisplayName("This Month")
        .description("Track this month's poker performance.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall])
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
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall])
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
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemLarge])
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
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogSessionLockScreenWidget: Widget {
    let kind = "LogSessionLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { _ in
            LockScreenShortcutWidgetView(
                destination: .manualLog,
                icon: "plus.circle.fill",
                title: "Log Session",
                subtitle: "Manual"
            )
        }
        .configurationDisplayName("Log Session")
        .description("Open Poker Bankroll AI to log a session.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AILogLockScreenWidget: Widget {
    let kind = "AILogLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { _ in
            LockScreenShortcutWidgetView(
                destination: .aiLog,
                icon: "sparkles",
                title: "AI Log",
                subtitle: "Chat"
            )
        }
        .configurationDisplayName("AI Log")
        .description("Open Poker Bankroll AI to log a session with AI.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct OddsLockScreenWidget: Widget {
    let kind = "OddsLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PokerWidgetProvider()) { _ in
            LockScreenShortcutWidgetView(
                destination: .odds,
                icon: "percent",
                title: "Odds",
                subtitle: "Calculate"
            )
        }
        .configurationDisplayName("Calculate Odds")
        .description("Open Poker Bankroll AI to calculate poker odds.")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct BankrollSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "chart.line.uptrend.xyaxis", destination: .home) {
            VStack(alignment: .leading, spacing: WidgetMetrics.verticalSpacing(for: family)) {
                WidgetHeader(title: "Bankroll", subtitle: "All time")

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.snapshot.bankrollText)
                        .font(.system(size: family == .systemSmall ? 27 : 33, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.snapshot.profitColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(entry.snapshot.profitText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.snapshot.profitColor)
                        .lineLimit(1)
                }

                if family == .systemMedium {
                    HStack(spacing: 10) {
                        StatPill(label: "Sessions", value: entry.snapshot.sessionCountText)
                        StatPill(label: "Win Rate", value: entry.snapshot.winRateText)
                        if let hourlyRateText = entry.snapshot.hourlyRateText {
                            StatPill(label: "Hourly", value: compactHourlyText(hourlyRateText))
                        }
                    }
                } else {
                    MetricStrip(metrics: [
                        WidgetMetric(label: "Sessions", value: entry.snapshot.sessionCountText),
                        WidgetMetric(label: "Win", value: entry.snapshot.winRateText),
                        WidgetMetric(label: "Hourly", value: compactHourlyText(entry.snapshot.hourlyRateText))
                    ])
                }
            }
        }
    }
}

private struct MonthlyProfitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "calendar", destination: .stats) {
            VStack(alignment: .leading, spacing: WidgetMetrics.verticalSpacing(for: family)) {
                WidgetHeader(title: "This Month", subtitle: "Performance")

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.monthProfitText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.snapshot.monthProfitColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer(minLength: 0)

                MetricStrip(metrics: [
                    WidgetMetric(label: "Sessions", value: entry.snapshot.monthSessionCountText),
                    WidgetMetric(label: "Win", value: entry.snapshot.monthWinRateText),
                    WidgetMetric(label: "Hourly", value: compactHourlyText(entry.snapshot.monthHourlyRateText))
                ])
            }
        }
    }
}

private struct LatestSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "clock.arrow.circlepath", destination: .sessions) {
            if let latestSession = entry.snapshot.latestSession {
                VStack(alignment: .leading, spacing: WidgetMetrics.verticalSpacing(for: family)) {
                    WidgetHeader(title: "Latest", subtitle: latestSession.dateText)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(latestSession.amountText)
                            .font(.system(size: family == .systemSmall ? 30 : 36, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.snapshot.color(isProfit: latestSession.isProfit))
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
    let entry: PokerWidgetEntry

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: gridSpacing),
            count: 7
        )
    }

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: nil, destination: .calendar) {
            VStack(alignment: .leading, spacing: verticalSpacing) {
                CalendarWidgetHeader(snapshot: entry.snapshot)

                HStack(spacing: gridSpacing) {
                    ForEach(Array(entry.snapshot.calendarWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: weekdayFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(displayedCalendarDays) { day in
                        CalendarWidgetDayCell(
                            day: day,
                            snapshot: entry.snapshot,
                            showAmount: family == .systemLarge,
                            isCompact: family == .systemSmall,
                            isLarge: family == .systemLarge,
                            height: dayCellHeight
                        )
                    }
                }

                if family == .systemLarge {
                    MetricStrip(metrics: [
                        WidgetMetric(label: "This Month", value: entry.snapshot.monthProfitText),
                        WidgetMetric(label: "Sessions", value: entry.snapshot.monthSessionCountText),
                        WidgetMetric(label: "Win", value: entry.snapshot.monthWinRateText),
                        WidgetMetric(label: "Hourly", value: compactHourlyText(entry.snapshot.monthHourlyRateText))
                    ])
                }
            }
        }
    }

    private var gridSpacing: CGFloat {
        family == .systemLarge ? 3 : 2
    }

    private var verticalSpacing: CGFloat {
        family == .systemLarge ? 5 : 4
    }

    private var weekdayFontSize: CGFloat {
        family == .systemLarge ? 10.5 : 8.5
    }

    private var dayCellHeight: CGFloat? {
        if family == .systemLarge {
            return displayedCalendarDays.count <= 35 ? 48 : 36
        }
        if family == .systemSmall {
            return displayedCalendarDays.count <= 35 ? 17 : 14.5
        }
        return nil
    }

    private var displayedCalendarDays: [PokerWidgetSnapshot.CalendarDay] {
        let days = entry.snapshot.calendarDays
        guard (family == .systemLarge || family == .systemSmall),
              days.count > 35,
              days.suffix(7).allSatisfy({ !$0.isInMonth }) else {
            return days
        }
        return Array(days.dropLast(7))
    }
}

private struct PokerShortcutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokerWidgetEntry

    var body: some View {
        WidgetShell(snapshot: entry.snapshot, icon: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 11) {
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
                    WidgetHeader(title: "Shortcuts", subtitle: "Quick actions")

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

private struct LockScreenShortcutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let destination: PokerShortcutDestination
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        content
            .widgetURL(PokerWidgetDeepLink.url(for: destination.route))
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        default:
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)
                    .widgetAccentable()
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WidgetShell<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PokerWidgetSnapshot
    let icon: String?
    let destination: PokerShortcutDestination?
    let content: Content

    init(
        snapshot: PokerWidgetSnapshot,
        icon: String?,
        destination: PokerShortcutDestination? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.snapshot = snapshot
        self.icon = icon
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        if let destination {
            Link(destination: PokerWidgetDeepLink.url(for: destination.route)) {
                shellContent
            }
        } else {
            shellContent
        }
    }

    private var shellContent: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(widgetPadding)
        .containerBackground(for: .widget) {
            WidgetPalette.background
        }
        .contentShape(Rectangle())
    }

    private var widgetPadding: CGFloat {
        family == .systemSmall ? 14 : 15
    }
}

private struct CalendarWidgetDayCell: View {
    let day: PokerWidgetSnapshot.CalendarDay
    let snapshot: PokerWidgetSnapshot
    let showAmount: Bool
    let isCompact: Bool
    let isLarge: Bool
    let height: CGFloat?

    var body: some View {
        VStack(spacing: showAmount ? 2 : 0) {
            Text(day.dayText)
                .font(.system(size: dayFontSize, weight: day.isToday ? .bold : .semibold, design: .rounded))
                .foregroundStyle(day.isInMonth ? Color.primary : Color.clear)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if showAmount, let amountText = day.amountText {
                Text(amountText)
                    .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(snapshot.color(isProfit: day.isProfit))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            } else {
                Circle()
                    .fill(day.hasSession ? snapshot.color(isProfit: day.isProfit) : Color.clear)
                    .frame(width: isCompact ? 3.5 : 4, height: isCompact ? 3.5 : 4)
            }
        }
        .frame(height: cellHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(dayBackground)
        )
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WidgetPalette.accent.opacity(0.65), lineWidth: 1.2)
            }
        }
        .opacity(day.isInMonth ? 1 : 0)
    }

    private var dayBackground: Color {
        if day.isToday {
            return WidgetPalette.accent.opacity(0.14)
        }
        if day.hasSession {
            return snapshot.color(isProfit: day.isProfit).opacity(0.14)
        }
        return Color(UIColor.secondarySystemGroupedBackground).opacity(isLarge ? 0.42 : isCompact ? 0.28 : 0.34)
    }

    private var dayFontSize: CGFloat {
        if isLarge { return 15 }
        if showAmount { return 8.2 }
        return isCompact ? 9.5 : 9.2
    }

    private var amountFontSize: CGFloat {
        isLarge ? 8.6 : 5.8
    }

    private var cellHeight: CGFloat {
        if let height { return height }
        if isLarge { return 28 }
        if showAmount { return 16 }
        return isCompact ? 13 : 16
    }

    private var cornerRadius: CGFloat {
        isLarge ? 8 : isCompact ? 7 : 7
    }
}

private struct CalendarWidgetHeader: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PokerWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.calendarMonthTitle)
                    .font(.system(size: family == .systemLarge ? 19 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                Text(snapshot.monthProfitText)
                    .font(.system(size: family == .systemLarge ? 17 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.monthProfitColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .padding(.trailing, 2)
    }
}

private struct ShortcutButton: View {
    @Environment(\.widgetFamily) private var family
    let destination: PokerShortcutDestination
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Link(destination: PokerWidgetDeepLink.url(for: destination.route)) {
            buttonContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, family == .systemSmall ? 10 : 11)
            .padding(.vertical, family == .systemSmall ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: WidgetMetrics.smallCornerRadius, style: .continuous)
                    .fill(WidgetPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WidgetMetrics.smallCornerRadius, style: .continuous)
                    .stroke(WidgetPalette.hairline, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: WidgetMetrics.smallCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        if family == .systemSmall {
            HStack(spacing: 8) {
                shortcutIcon
                    .frame(width: 19)
                VStack(alignment: .leading, spacing: 0) {
                    titleText
                    subtitleText
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                shortcutIcon
                VStack(alignment: .leading, spacing: 1) {
                    titleText
                    subtitleText
                }
            }
        }
    }

    private var shortcutIcon: some View {
        Image(systemName: icon)
            .font(.system(size: family == .systemSmall ? 16 : 18, weight: .bold))
            .foregroundStyle(WidgetPalette.accent)
            .symbolRenderingMode(.hierarchical)
    }

    private var titleText: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct WidgetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct WidgetMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct MetricStrip: View {
    let metrics: [WidgetMetric]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(metrics) { metric in
                CompactStat(label: metric.label, value: metric.value)
            }
        }
    }
}

private struct CompactStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.card.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WidgetPalette.hairline, lineWidth: 0.5)
        )
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
            RoundedRectangle(cornerRadius: WidgetMetrics.smallCornerRadius, style: .continuous)
                .fill(WidgetPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WidgetMetrics.smallCornerRadius, style: .continuous)
                .stroke(WidgetPalette.hairline, lineWidth: 0.5)
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
    static let accent = Color.blue
    static let background = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.06)
}

private enum WidgetMetrics {
    static let smallCornerRadius: CGFloat = 10

    static func verticalSpacing(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? 9 : 12
    }
}

private func compactHourlyText(_ text: String?) -> String {
    guard let text, !text.isEmpty else { return "--" }
    let compactText = text.replacingOccurrences(of: "/hr", with: "")
    guard !compactText.localizedCaseInsensitiveContains("K"),
          !compactText.localizedCaseInsensitiveContains("M"),
          let firstDigit = compactText.firstIndex(where: { $0.isNumber }) else {
        return compactText
    }

    var numberEnd = firstDigit
    while numberEnd < compactText.endIndex {
        let character = compactText[numberEnd]
        guard character.isNumber || character == "." else { break }
        numberEnd = compactText.index(after: numberEnd)
    }

    let numberText = String(compactText[firstDigit..<numberEnd])
    guard let value = Double(numberText) else { return compactText }
    let prefix = compactText[..<firstDigit]
    let suffix = compactText[numberEnd...]
    return "\(prefix)\(Int(value.rounded()))\(suffix)"
}

private extension PokerWidgetSnapshot {
    var profitColor: Color {
        color(isProfit: isProfit)
    }

    var monthProfitColor: Color {
        color(isProfit: isMonthProfit)
    }

    func color(isProfit: Bool) -> Color {
        let displayColor = isProfit ? winColor : lossColor
        return Color(red: displayColor.red, green: displayColor.green, blue: displayColor.blue)
    }
}

enum PokerShortcutDestination: String, AppEnum {
    case home
    case stats
    case odds
    case aiLog
    case manualLog
    case calendar
    case sessions

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Poker Shortcut")
    static var caseDisplayRepresentations: [PokerShortcutDestination: DisplayRepresentation] = [
        .home: "Open Home",
        .stats: "Open Stats",
        .odds: "Calculate Odds",
        .aiLog: "AI Log Session",
        .manualLog: "Manual Log Session",
        .calendar: "Open Calendar",
        .sessions: "Open Sessions"
    ]

    var route: PokerWidgetRoute {
        switch self {
        case .home: return .home
        case .stats: return .stats
        case .odds: return .odds
        case .aiLog: return .aiLog
        case .manualLog: return .manualLog
        case .calendar: return .calendar
        case .sessions: return .sessions
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
