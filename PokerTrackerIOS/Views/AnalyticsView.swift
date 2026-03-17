//
//  AnalyticsView.swift
//  PokerTrackerIOS
//

import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var showingDateRange = false
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var profitBreakdownDimension: ProfitBreakdownDimension = .venue
    
    private var currency: String { settingsStore.settings.currency }
    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }

    private var currentStreakDisplay: (value: String, color: Color) {
        guard let latestSession = sessionStore.filteredSessions.first else {
            return ("0", .secondary)
        }
        if latestSession.isWin {
            return ("\(sessionStore.currentWinStreak)W", winColor)
        }
        if latestSession.isLoss {
            return ("\(sessionStore.currentLossStreak)L", lossColor)
        }
        return ("Even", .secondary)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if sessionStore.filterDateFrom != nil || sessionStore.filterDateTo != nil {
                        dateRangeBanner
                    }
                    summaryCards

                    if subscriptionStore.isSubscribed {
                        if sessionStore.profitOverTime.count >= 2 {
                            profitLineChart
                        }
                        if sessionStore.drawdownOverTime.count >= 2 {
                            drawdownChart
                        }
                        if sessionStore.totalSessions > 0 {
                            winLossChart
                        }
                        if sessionStore.monthlyProfit.count >= 2 {
                            monthlyBarChart
                        }
                        if sessionStore.totalSessions > 0 {
                            profitBreakdownChart
                        }
                    } else {
                        chartsLockedSection
                    }

                    if sessionStore.totalSessions > 0 {
                        detailStats
                    }
                }
                .padding()
                .id(sessionStore.dataVersion)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stats")
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDateRange = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .sheet(isPresented: $showingDateRange) {
                StatsDateRangeSheet()
                    .environmentObject(sessionStore)
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var chartsLockedSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accent.opacity(0.5))
            }
            Text("Charts are part of Premium")
                .font(.title3.weight(.semibold))
            Text("Subscribe to see cumulative profit, win/loss, monthly results, and profit breakdowns by venue, game type, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingPaywall = true
            } label: {
                Text("Unlock Premium — 1 Month Free")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius, style: .continuous)
                            .fill(AppTheme.accent)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var dateRangeBanner: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(AppTheme.accent)
            Text(dateRangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                sessionStore.filterDateFrom = nil
                sessionStore.filterDateTo = nil
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .subtleCard()
    }
    
    private var chartDomain: ClosedRange<Date> {
        guard let range = sessionStore.chartDateRange else {
            let d = Date()
            return d...d
        }
        return range.start...range.end
    }
    
    /// Domain for monthly chart: months with data only
    private var monthlyChartDomain: ClosedRange<Date>? {
        guard let range = sessionStore.monthlyChartDomain else { return nil }
        return range.start...range.end
    }
    
    /// Tight domain for cumulative profit (data range only)
    private var cumulativeProfitDomain: ClosedRange<Date> {
        guard let range = sessionStore.cumulativeProfitDomain else { return chartDomain }
        return range.start...range.end
    }
    
    private var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if let from = sessionStore.filterDateFrom, let to = sessionStore.filterDateTo {
            return "\(formatter.string(from: from)) – \(formatter.string(from: to))"
        }
        if let from = sessionStore.filterDateFrom {
            return "From \(formatter.string(from: from))"
        }
        if let to = sessionStore.filterDateTo {
            return "Until \(formatter.string(from: to))"
        }
        return ""
    }
    
    // MARK: - Summary Cards
    
    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryCard("Total P/L", PokerSession.formatCurrency(sessionStore.totalProfit, currency: currency), sessionStore.totalProfit >= 0 ? winColor : lossColor)
            summaryCard("Sessions", "\(sessionStore.totalSessions)", AppTheme.accent)
            summaryCard("Win Rate", String(format: "%.0f%%", sessionStore.winRate), AppTheme.accent)
            summaryCard("Avg Session", PokerSession.formatCurrency(sessionStore.averageSession, currency: currency), sessionStore.averageSession >= 0 ? winColor : lossColor)
        }
    }
    
    private func summaryCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .cardStyle()
    }
    
    // MARK: - Profit Over Time Line Chart
    
    private var profitLineChart: some View {
        let data = sessionStore.profitOverTime
        let color: Color = sessionStore.totalProfit >= 0 ? winColor : lossColor
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cumulative Profit")
                .font(.headline)
            
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.0, unit: .day),
                        y: .value("Profit", point.1)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.stepEnd)
                    
                    AreaMark(
                        x: .value("Date", point.0, unit: .day),
                        y: .value("Profit", point.1)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.stepEnd)
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .frame(height: 200)
            .chartXScale(domain: cumulativeProfitDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.caption2)
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    // MARK: - Win/Loss Donut
    
    private var winLossChart: some View {
        let breakEvenColor = Color.secondary
        return VStack(alignment: .leading, spacing: 8) {
            Text("Win / Loss")
                .font(.headline)
            
            HStack(spacing: 20) {
                Chart {
                    if sessionStore.winCount > 0 {
                        SectorMark(angle: .value("Wins", sessionStore.winCount), innerRadius: .ratio(0.6))
                            .foregroundStyle(winColor)
                    }
                    if sessionStore.lossCount > 0 {
                        SectorMark(angle: .value("Losses", sessionStore.lossCount), innerRadius: .ratio(0.6))
                            .foregroundStyle(lossColor)
                    }
                    if sessionStore.breakEvenCount > 0 {
                        SectorMark(angle: .value("Break-even", sessionStore.breakEvenCount), innerRadius: .ratio(0.6))
                            .foregroundStyle(breakEvenColor)
                    }
                }
                .frame(width: 120, height: 120)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(winColor).frame(width: 10, height: 10)
                        Text("\(sessionStore.winCount) Wins")
                            .font(.subheadline)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(lossColor).frame(width: 10, height: 10)
                        Text("\(sessionStore.lossCount) Losses")
                            .font(.subheadline)
                    }
                    if sessionStore.breakEvenCount > 0 {
                        HStack(spacing: 6) {
                            Circle().fill(breakEvenColor).frame(width: 10, height: 10)
                            Text("\(sessionStore.breakEvenCount) Break-even")
                                .font(.subheadline)
                        }
                    }
                    if let best = sessionStore.bestSession {
                        Text("Best: \(PokerSession.formatCurrency(best.amount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(winColor)
                    }
                    if let worst = sessionStore.worstSession {
                        Text("Worst: \(PokerSession.formatCurrency(worst.amount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(lossColor)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Drawdown Chart

    private var drawdownChart: some View {
        let data = sessionStore.drawdownOverTime
        let minDrawdown = data.map(\.1).min() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Drawdown Over Time")
                .font(.headline)

            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.0, unit: .day),
                        y: .value("Drawdown", point.1)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lossColor.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.stepEnd)

                    LineMark(
                        x: .value("Date", point.0, unit: .day),
                        y: .value("Drawdown", point.1)
                    )
                    .foregroundStyle(lossColor)
                    .interpolationMethod(.stepEnd)
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .frame(height: 190)
            .chartXScale(domain: cumulativeProfitDomain)
            .chartYScale(domain: minDrawdown...0)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.caption2)
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    // MARK: - Monthly Bar Chart
    
    private var monthlyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Results")
                .font(.headline)
            
            Chart {
                ForEach(sessionStore.monthlyProfitWithDates, id: \.0) { monthDate, profit in
                    BarMark(
                        x: .value("Month", monthDate, unit: .month),
                        y: .value("Profit", profit),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(profit >= 0 ? winColor : lossColor)
                    .cornerRadius(4)
                }
            }
            .frame(height: 220)
            .chartXScale(domain: monthlyChartDomain ?? chartDomain)
            .chartPlotStyle { plotArea in
                plotArea.padding(.horizontal, 8)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Profit Breakdown

    private var profitBreakdownChart: some View {
        let data = sessionStore.profitBreakdown(for: profitBreakdownDimension)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profit Breakdown")
                        .font(.headline)
                    Text("By \(profitBreakdownDimension.rawValue)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Picker("Profit Breakdown", selection: $profitBreakdownDimension) {
                    ForEach(ProfitBreakdownDimension.allCases) { dimension in
                        Text(dimension.rawValue).tag(dimension)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if data.isEmpty {
                Text("No \(profitBreakdownDimension.rawValue.lowercased()) data in this range yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    RuleMark(x: .value("Zero", 0))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [5, 5]))

                    ForEach(data) { entry in
                        BarMark(
                            x: .value("Profit", entry.profit),
                            y: .value("Category", entry.label)
                        )
                        .foregroundStyle(entry.profit >= 0 ? winColor : lossColor)
                        .cornerRadius(5)
                    }
                }
                .frame(height: profitBreakdownChartHeight(for: data.count))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(shortCurrency(amount))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                            }
                        }
                    }
                }

                Text("\(data.count) categories • \(data.reduce(0) { $0 + $1.sessions }) sessions")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding()
        .cardStyle()
    }
    
    // MARK: - Detail Stats
    
    private var detailStats: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessionStore.thisMonthProfit != 0 {
                detailRow("This Month", PokerSession.formatCurrency(sessionStore.thisMonthProfit, currency: currency), sessionStore.thisMonthProfit >= 0 ? winColor : lossColor)
                Divider()
            }
            if sessionStore.totalHoursPlayed > 0 {
                detailRow("Total Hours", String(format: "%.1f", sessionStore.totalHoursPlayed), .primary)
                if settingsStore.settings.showHourlyRate, let rate = sessionStore.hourlyRate {
                    Divider()
                    detailRow("Hourly Rate", PokerSession.formatCurrency(rate, currency: currency) + "/hr", rate >= 0 ? winColor : lossColor)
                }
                Divider()
            }
            if sessionStore.longestWinStreak > 0 {
                detailRow("Best Streak", "\(sessionStore.longestWinStreak) wins", winColor)
                Divider()
            }
            detailRow("Current Streak", currentStreakDisplay.value, currentStreakDisplay.color)
        }
        .padding()
        .cardStyle()
    }
    
    private func detailRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }
    
    private func shortCurrency(_ value: Double) -> String {
        let prefix = value < 0 ? "-" : ""
        return prefix + PokerSession.formatCompactCurrency(abs(value), currency: currency)
    }

    private func profitBreakdownChartHeight(for count: Int) -> CGFloat {
        CGFloat(max(count, 3)) * 34
    }
}

// MARK: - Stats Date Range Sheet

struct StatsDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    
    private var calendar: Calendar { .current }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        sessionStore.filterDateFrom = nil
                        sessionStore.filterDateTo = nil
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text("All (Earliest session – Today)")
                        }
                    }
                    
                    presetButton("Last 30 days") {
                        let end = Date()
                        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
                        apply(start: start, end: end)
                    }
                    presetButton("Last 90 days") {
                        let end = Date()
                        let start = calendar.date(byAdding: .day, value: -90, to: end) ?? end
                        apply(start: start, end: end)
                    }
                    presetButton("This year") {
                        let end = Date()
                        let start = calendar.date(from: calendar.dateComponents([.year], from: end)) ?? end
                        apply(start: start, end: end)
                    }
                } header: {
                    Text("Presets")
                }
                
                Section("Custom range") {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                    DatePicker("To", selection: $dateTo, displayedComponents: .date)
                    Button("Apply custom range") {
                        let start = min(dateFrom, dateTo)
                        let end = max(dateFrom, dateTo)
                        apply(start: start, end: end)
                    }
                }
            }
            .navigationTitle("Date range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Date range")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let range = sessionStore.allSessionsDateRange {
                    dateFrom = sessionStore.filterDateFrom ?? range.start
                    dateTo = sessionStore.filterDateTo ?? range.end
                }
            }
        }
    }
    
    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
    }
    
    private func apply(start: Date, end: Date) {
        sessionStore.filterDateFrom = start
        sessionStore.filterDateTo = end
        dismiss()
    }
}

private struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
            .environmentObject(SubscriptionStore.shared)
    }
}
