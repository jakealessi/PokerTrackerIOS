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
    @State private var showingFilters = false
    @State private var showingPaywall = false
    @State private var profitBreakdownDimension: ProfitBreakdownDimension = .venue
    @State private var hourlyRateBreakdownDimension: HourlyRateBreakdownDimension = .venue
    
    private var currency: String { settingsStore.settings.currency }
    private var drawdownColor: Color { Color(uiColor: .systemGray) }
    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }
    private var premiumCTAButtonTitle: String {
        if subscriptionStore.proMonthlyProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Unlock Premium — Start Free Trial"
        }
        return "Unlock Premium"
    }

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
                    if sessionStore.hasActiveSessionFilters {
                        activeFiltersBanner
                    }
                    summaryCards

                    if subscriptionStore.isSubscribed {
                        if sessionStore.profitOverTime.count >= 2 {
                            profitLineChart
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
                        if sessionStore.totalSessions > 0 {
                            hourlyRateBreakdownChart
                        }
                        if sessionStore.drawdownOverTime.count >= 2 {
                            drawdownChart
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stats")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: sessionStore.hasActiveSessionFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView()
                    .environmentObject(sessionStore)
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
            }
        }
    }

    private var chartsLockedSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.4))

            Text("Charts are part of Premium")
                .font(.headline)

            Text("Cumulative profit, drawdown, monthly results, hourly rate, and profit breakdowns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingPaywall = true
            } label: {
                Text(premiumCTAButtonTitle)
                    .font(.subheadline.weight(.semibold))
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

    private var activeFiltersBanner: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(sessionStore.activeFilterLabels.joined(separator: " • "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button("Clear") {
                sessionStore.clearFilters()
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
    
    // MARK: - Summary Cards
    
    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryCard("Net P/L", PokerSession.formatCurrency(sessionStore.totalProfit, currency: currency), sessionStore.totalProfit >= 0 ? winColor : lossColor)
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
            Text("Cumulative Net Profit")
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
                        Text("Best: \(PokerSession.formatCurrency(best.netAmount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(best.netAmount >= 0 ? winColor : lossColor)
                    }
                    if let worst = sessionStore.worstSession {
                        Text("Worst: \(PokerSession.formatCurrency(worst.netAmount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(worst.netAmount >= 0 ? winColor : lossColor)
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
                            colors: [drawdownColor.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.stepEnd)

                    LineMark(
                        x: .value("Date", point.0, unit: .day),
                        y: .value("Drawdown", point.1)
                    )
                    .foregroundStyle(drawdownColor)
                    .interpolationMethod(.stepEnd)
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .frame(height: 190)
            .chartXScale(domain: cumulativeProfitDomain)
            .chartYScale(domain: drawdownDomain(for: data))
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

    private func drawdownDomain(for data: [(Date, Double)]) -> ClosedRange<Double> {
        let minDrawdown = data.map(\.1).min() ?? 0
        if minDrawdown < 0 {
            return minDrawdown...0
        }
        // Charts misbehave with a collapsed 0...0 range on all-up graphs.
        return -1...0
    }
    
    // MARK: - Monthly Bar Chart
    
    private var monthlyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Net Results")
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
                    Text("Net Profit Breakdown")
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

    // MARK: - Hourly Rate Breakdown

    private var hourlyRateBreakdownChart: some View {
        let data = sessionStore.hourlyRateBreakdown(for: hourlyRateBreakdownDimension)
        let totalSessions = data.reduce(0) { $0 + $1.sessions }
        let totalHours = data.reduce(0) { $0 + $1.totalHours }
        let bestEntry = data.max { lhs, rhs in
            if lhs.hourlyRate != rhs.hourlyRate { return lhs.hourlyRate < rhs.hourlyRate }
            if lhs.totalHours != rhs.totalHours { return lhs.totalHours < rhs.totalHours }
            if lhs.sessions != rhs.sessions { return lhs.sessions < rhs.sessions }
            return lhs.label > rhs.label
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hourly Rate Breakdown")
                        .font(.headline)
                    Text("By \(hourlyRateBreakdownDimension.rawValue)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Picker("Hourly Rate Breakdown", selection: $hourlyRateBreakdownDimension) {
                    ForEach(HourlyRateBreakdownDimension.allCases) { dimension in
                        Text(dimension.rawValue).tag(dimension)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if data.isEmpty {
                Text(hourlyRateBreakdownEmptyStateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    RuleMark(x: .value("Zero", 0))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [5, 5]))

                    ForEach(data) { entry in
                        BarMark(
                            x: .value("Hourly Rate", entry.hourlyRate),
                            y: .value("Category", entry.label)
                        )
                        .foregroundStyle(entry.hourlyRate >= 0 ? winColor : lossColor)
                        .cornerRadius(5)
                    }
                }
                .frame(height: profitBreakdownChartHeight(for: data.count))
                .chartXScale(domain: hourlyRateDomain(for: data))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hourlyRate = value.as(Double.self) {
                                Text(shortCurrency(hourlyRate))
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

                if let bestEntry {
                    Text("\(totalSessions) \(hourlyRateBreakdownSessionLabel) • \(formattedHours(totalHours)) hours • \(bestCategoryPrefix) \(bestEntry.label) at \(formattedHourlyRate(bestEntry.hourlyRate)) over \(formattedHours(bestEntry.totalHours)) hours")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("\(totalSessions) \(hourlyRateBreakdownSessionLabel) • \(formattedHours(totalHours)) hours")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
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
            if sessionStore.totalExpenses > 0 {
                detailRow("Expenses", PokerSession.formatCurrency(sessionStore.totalExpenses, currency: currency), lossColor)
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
        settingsStore.settings.displayAmount(value, compact: true, includePositiveSign: false)
    }

    private func formattedHourlyRate(_ value: Double) -> String {
        settingsStore.settings.displayAmount(value, compact: false, includePositiveSign: false) + "/hr"
    }

    private func formattedHours(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func hourlyRateDomain(for data: [HourlyRateBreakdownEntry]) -> ClosedRange<Double> {
        let values = data.map(\.hourlyRate)
        guard let minValue = values.min(), let maxValue = values.max() else { return -1...1 }
        if minValue == 0, maxValue == 0 { return -1...1 }

        let span = maxValue - minValue
        let magnitude = max(abs(minValue), abs(maxValue))
        let padding = max(span * 0.1, magnitude * 0.1, 0.5)

        if minValue >= 0 {
            return 0...(maxValue + padding)
        }
        if maxValue <= 0 {
            return (minValue - padding)...0
        }
        return (minValue - padding)...(maxValue + padding)
    }

    private var hourlyRateBreakdownEmptyStateText: String {
        switch hourlyRateBreakdownDimension {
        case .venue:
            return "No venue data with logged hours in this range yet."
        case .gameType:
            return "No game type data with logged hours in this range yet."
        case .variant:
            return "No variant data with logged hours in this range yet."
        case .stakes:
            return "No stakes data with logged hours in this range yet."
        case .weekday:
            return "No weekday data with logged hours in this range yet."
        }
    }

    private var hourlyRateBreakdownSessionLabel: String {
        "sessions with hours"
    }

    private var bestCategoryPrefix: String {
        switch hourlyRateBreakdownDimension {
        case .venue:
            return "Best venue:"
        case .gameType:
            return "Best game type:"
        case .variant:
            return "Best variant:"
        case .stakes:
            return "Best stakes:"
        case .weekday:
            return "Best weekday:"
        }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Date Range")
                        .font(.headline.weight(.semibold))
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
