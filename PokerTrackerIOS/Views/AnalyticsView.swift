//
//  AnalyticsView.swift
//  PokerTrackerIOS
//

import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    
    private var currency: String { settingsStore.settings.currency }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCards
                    
                    if sessionStore.profitOverTime.count >= 2 {
                        profitLineChart
                    }
                    
                    if sessionStore.totalSessions > 0 {
                        winLossChart
                    }
                    
                    if sessionStore.monthlyProfit.count >= 2 {
                        monthlyBarChart
                    }
                    
                    if sessionStore.sessionsByVariant.count >= 2 {
                        variantBreakdown
                    }
                    
                    detailStats
                }
                .padding()
            }
            .navigationTitle("Stats")
        }
    }
    
    // MARK: - Summary Cards
    
    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryCard("Total P/L", PokerSession.formatCurrency(sessionStore.totalProfit, currency: currency), sessionStore.totalProfit >= 0 ? .green : .red)
            summaryCard("Sessions", "\(sessionStore.totalSessions)", AppTheme.accent)
            summaryCard("Win Rate", String(format: "%.0f%%", sessionStore.winRate), AppTheme.accent)
            summaryCard("Avg Session", PokerSession.formatCurrency(sessionStore.averageSession, currency: currency), sessionStore.averageSession >= 0 ? .green : .red)
        }
    }
    
    private func summaryCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Profit Over Time Line Chart
    
    private var profitLineChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cumulative Profit")
                .font(.headline)
            
            Chart {
                ForEach(Array(sessionStore.profitOverTime.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.0),
                        y: .value("Profit", point.1)
                    )
                    .foregroundStyle(sessionStore.totalProfit >= 0 ? Color.green : Color.red)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", point.0),
                        y: .value("Profit", point.1)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                (sessionStore.totalProfit >= 0 ? Color.green : Color.red).opacity(0.3),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .frame(height: 200)
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
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Win/Loss Donut
    
    private var winLossChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Win / Loss")
                .font(.headline)
            
            HStack(spacing: 20) {
                Chart {
                    SectorMark(angle: .value("Wins", sessionStore.winCount), innerRadius: .ratio(0.6))
                        .foregroundStyle(.green)
                    SectorMark(angle: .value("Losses", max(sessionStore.lossCount, 0)), innerRadius: .ratio(0.6))
                        .foregroundStyle(.red)
                }
                .frame(width: 120, height: 120)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 10, height: 10)
                        Text("\(sessionStore.winCount) Wins")
                            .font(.subheadline)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("\(sessionStore.lossCount) Losses")
                            .font(.subheadline)
                    }
                    if let best = sessionStore.bestSession {
                        Text("Best: \(PokerSession.formatCurrency(best.amount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let worst = sessionStore.worstSession {
                        Text("Worst: \(PokerSession.formatCurrency(worst.amount, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Monthly Bar Chart
    
    private var monthlyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Results")
                .font(.headline)
            
            Chart {
                ForEach(Array(sessionStore.monthlyProfit.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Month", item.0),
                        y: .value("Profit", item.1)
                    )
                    .foregroundStyle(item.1 >= 0 ? Color.green : Color.red)
                    .cornerRadius(4)
                }
            }
            .frame(height: 180)
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
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Variant Breakdown
    
    private var variantBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Variant")
                .font(.headline)
            
            let maxProfit = sessionStore.sessionsByVariant.map { abs($0.2) }.max() ?? 1
            
            ForEach(sessionStore.sessionsByVariant, id: \.0) { variant, count, profit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(variant)
                            .font(.subheadline)
                        Spacer()
                        Text(PokerSession.formatCurrency(profit, currency: currency))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(profit >= 0 ? .green : .red)
                    }
                    
                    GeometryReader { geo in
                        let barWidth = max(geo.size.width * CGFloat(abs(profit) / maxProfit), 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(profit >= 0 ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                            .frame(width: barWidth, height: 8)
                    }
                    .frame(height: 8)
                    
                    Text("\(count) sessions")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Detail Stats
    
    private var detailStats: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessionStore.thisMonthProfit != 0 {
                detailRow("This Month", PokerSession.formatCurrency(sessionStore.thisMonthProfit, currency: currency), sessionStore.thisMonthProfit >= 0 ? .green : .red)
                Divider()
            }
            if sessionStore.totalHoursPlayed > 0 {
                detailRow("Total Hours", String(format: "%.1f", sessionStore.totalHoursPlayed), .primary)
                Divider()
                if let rate = sessionStore.hourlyRate {
                    detailRow("Hourly Rate", PokerSession.formatCurrency(rate, currency: currency) + "/hr", rate >= 0 ? .green : .red)
                    Divider()
                }
            }
            if sessionStore.longestWinStreak > 0 {
                detailRow("Best Streak", "\(sessionStore.longestWinStreak) wins", .green)
                Divider()
            }
            detailRow("Current Streak", sessionStore.currentWinStreak > 0 ? "\(sessionStore.currentWinStreak)W" : "\(sessionStore.currentLossStreak)L", sessionStore.currentWinStreak > 0 ? .green : .red)
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
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
        if abs(value) >= 1000 {
            return String(format: "$%.0fk", value / 1000)
        }
        return String(format: "$%.0f", value)
    }
}

#Preview {
    AnalyticsView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
