//
//  DashboardView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct DashboardView: View {
    private struct DashboardMetric: Identifiable {
        let label: String
        let value: String
        let tint: Color

        var id: String { label }
    }

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var showingAddSession = false
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var chatEditSession: PokerSession?
    @State private var chatMessages: [ChatMessage] = []
    @State private var conversationId = UUID().uuidString
    @State private var inputText = ""
    @State private var isAILoading = false
    @State private var aiError: String?
    @FocusState private var inputFocused: Bool
    @State private var aiTask: Task<Void, Never>?
    
    private var bankroll: Double {
        settingsStore.settings.startingBankroll + allSessionsProfit
    }

    private var allSessions: [PokerSession] {
        sessionStore.sessions
    }

    private var settingsDefaultDeductExpenses: Bool { settingsStore.settings.deductExpensesFromProfit }
    private var allSessionsProfit: Double {
        allSessions.reduce(0) { $0 + $1.displayProfit(deductExpenses: $1.effectiveDeductExpenses(settingsDefault: settingsDefaultDeductExpenses)) }
    }

    private var allSessionsCount: Int {
        allSessions.count
    }

    private var allSessionsWinCount: Int {
        allSessions.filter(\.isWin).count
    }

    private var allSessionsLossCount: Int {
        allSessions.filter(\.isLoss).count
    }

    private var allSessionsWinRate: Double {
        guard allSessionsCount > 0 else { return 0 }
        return Double(allSessionsWinCount) / Double(allSessionsCount) * 100
    }

    private var allSessionsTotalHours: Double {
        allSessions.compactMap(\.hoursPlayed).reduce(0, +)
    }

    private var allSessionsHourlyRate: Double? {
        guard allSessionsTotalHours > 0 else { return nil }
        return allSessionsProfit / allSessionsTotalHours
    }

    private var canUseAISessionCrafter: Bool {
        subscriptionStore.isSubscribed || AISessionCrafterUsage.hasFreeUsesRemaining
    }
    
    private var winColor: Color { settingsStore.settings.profitLossColorScheme.winColor }
    private var lossColor: Color { settingsStore.settings.profitLossColorScheme.lossColor }
    private var hourlyRateLabel: String { "\(StakesPreset.symbol(for: settingsStore.settings.currency))/hr" }
    private var dashboardMetrics: [DashboardMetric] {
        var metrics = [
            DashboardMetric(label: "Sessions", value: "\(allSessionsCount)", tint: AppTheme.accent),
            DashboardMetric(label: "Win Rate", value: String(format: "%.0f%%", allSessionsWinRate), tint: AppTheme.accent),
            DashboardMetric(label: "W/L", value: "\(allSessionsWinCount)/\(allSessionsLossCount)", tint: AppTheme.accent)
        ]
        if settingsStore.settings.showHourlyRate,
           allSessionsTotalHours > 0,
           let rate = allSessionsHourlyRate {
            metrics.append(
                DashboardMetric(
                    label: hourlyRateLabel,
                    value: formatCurrencyTwoDecimals(rate),
                    tint: rate >= 0 ? winColor : lossColor
                )
            )
        }
        return metrics
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statsHeader
                chatArea
                inputBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Poker Bankroll AI")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        showingAddSession = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $chatEditSession) { session in
                EditSessionView(session: session)
            }
            .onDisappear {
                aiTask?.cancel()
            }
        }
    }
    
    // MARK: - Stats Header

    private var startingBankroll: Double { settingsStore.settings.startingBankroll }
    private var showProfitSeparately: Bool { startingBankroll != 0 }

    private var statsHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BANKROLL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                Text(formattedBankroll)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(bankroll >= 0 ? winColor : lossColor)
                    .contentTransition(.numericText())
                if showProfitSeparately {
                    Text("Profit: \(formattedProfit)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(allSessionsProfit >= 0 ? winColor : lossColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 12)

            HStack(spacing: 0) {
                ForEach(Array(dashboardMetrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 {
                        Spacer()
                    }
                    metricColumn(metric)
                    if index < dashboardMetrics.count - 1 {
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: AppTheme.subtleShadow.color, radius: AppTheme.subtleShadow.radius, y: AppTheme.subtleShadow.y)
        )
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var formattedBankroll: String {
        formatCurrencyTwoDecimals(bankroll)
    }

    private var formattedProfit: String {
        let formatted = formatCurrencyTwoDecimals(abs(allSessionsProfit))
        return allSessionsProfit >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private func formatCurrencyTwoDecimals(_ value: Double) -> String {
        let currency = settingsStore.settings.currency
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: SupportedCurrency.localeIdentifier(for: currency))
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? PokerSession.formatCurrency(value, currency: currency)
    }

    private func metricColumn(_ metric: DashboardMetric) -> some View {
        VStack(spacing: 3) {
            Text(metric.value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(metric.tint)
                .monospacedDigit()
            Text(metric.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Chat Area
    
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if chatMessages.isEmpty {
                    emptyPrompt
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            inputFocused = true
                        }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(chatMessages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }
                        
                        if isAILoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: chatMessages.count) { _, _ in
                withAnimation(AppTheme.smoothSpring) {
                    if let last = chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isAILoading) { _, loading in
                if loading {
                    withAnimation(AppTheme.smoothSpring) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.35))

            VStack(spacing: 6) {
                Text("Log a Session")
                    .font(.headline)

                Text("Describe your session below and AI will log it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("\"Won $200 at 1/2 NLH for 4 hours\"")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accent.opacity(0.7))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.06))
                )

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
    
    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }

            chatMessageContent(message)
                .frame(maxWidth: 340, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func chatMessageContent(_ message: ChatMessage) -> some View {
        if message.role == .assistant,
           let card = message.card,
           case .session(let payload) = card,
           let session = sessionStore.sessions.first(where: { $0.id == payload.sessionID }) {
            assistantSessionCard(payload, session: session)
        } else {
            standardChatBubble(message)
        }
    }

    private func standardChatBubble(_ message: ChatMessage) -> some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(message.role == .user ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                ? AnyShapeStyle(AppTheme.accent)
                : AnyShapeStyle(AppTheme.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(message.role == .user ? 0.06 : 0.03), radius: 3, y: 1)
    }

    private func assistantSessionCard(_ payload: ChatMessage.SessionCard, session: PokerSession) -> some View {
        let deductExpenses = session.effectiveDeductExpenses(settingsDefault: settingsDefaultDeductExpenses)
        let sessionTint: Color = {
            if session.isWinForDisplay(deductExpenses: deductExpenses) { return winColor }
            if session.isLossForDisplay(deductExpenses: deductExpenses) { return lossColor }
            return .secondary
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: payload.systemImage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                Text(payload.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)

                Spacer(minLength: 4)

                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    chatEditSession = sessionStore.sessions.first(where: { $0.id == session.id }) ?? session
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.accent.opacity(0.1))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(PokerSession.formatCurrency(session.displayProfit(deductExpenses: deductExpenses), currency: settingsStore.settings.currency))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(sessionTint)
                .monospacedDigit()

            Text(sessionCardPrimaryMeta(session))
                .font(.subheadline.weight(.medium))

            HStack(spacing: 14) {
                Label(session.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                if let venue = session.venue, !venue.isEmpty {
                    Label(venue, systemImage: "mappin")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if session.hasExpenses || !(payload.detail ?? "").isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if session.hasExpenses {
                        Text("Gross \(PokerSession.formatCurrency(session.amount, currency: settingsStore.settings.currency)) · Expenses \(PokerSession.formatCurrency(session.totalExpenses, currency: settingsStore.settings.currency))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let detail = payload.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(sessionTint.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func sessionCardPrimaryMeta(_ session: PokerSession) -> String {
        var parts = [session.displayVariantAbbreviation, session.displayGameTypeAbbreviation]
        if let stakes = session.stakes, !stakes.isEmpty {
            parts.append(stakes)
        }
        if let hours = session.hoursPlayed, hours > 0 {
            parts.append("\(String(format: "%.1f", hours))h")
        }
        return parts.joined(separator: " · ")
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            if let error = aiError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if !subscriptionStore.isSubscribed && AISessionCrafterUsage.usesRemaining < AISessionCrafterUsage.freeUseLimit {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent)
                    Text("\(AISessionCrafterUsage.usesRemaining) of \(AISessionCrafterUsage.freeUseLimit) free uses left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if AISessionCrafterUsage.usesRemaining == 0 {
                        Button("Upgrade") {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            showingPaywall = true
                        }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()
            
            HStack(alignment: .bottom, spacing: 8) {
                if !chatMessages.isEmpty {
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        aiTask?.cancel()
                        withAnimation(AppTheme.smoothSpring) {
                            chatMessages.removeAll()
                            conversationId = UUID().uuidString
                            aiError = nil
                            isAILoading = false
                        }
                    } label: {
                        Image(systemName: "plus.message")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                }
                
                TextField("Log a session...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                    .focused($inputFocused)
                
                if inputFocused {
                    Button {
                        inputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(AppTheme.cardBackground)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                    }
                    .accessibilityLabel("Done")
                    .transition(.opacity.combined(with: .scale))
                }

                Button {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading
                            ? Color.secondary.opacity(0.65) : .white
                        )
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(
                                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading
                                    ? Color(UIColor.systemGray5) : AppTheme.accent
                                )
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(AppTheme.smoothSpring, value: inputFocused)
        }
    }
    
    // MARK: - Send & AI Logic
    
    @MainActor
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !canUseAISessionCrafter {
            showingPaywall = true
            return
        }

        withAnimation(AppTheme.smoothSpring) {
            chatMessages.append(ChatMessage(role: .user, text: text))
        }
        inputText = ""
        aiError = nil
        
        aiTask?.cancel()
        aiTask = Task { await processWithAI() }
    }
    
    @MainActor
    private func processWithAI() async {
        defer { isAILoading = false }
        guard !Task.isCancelled else { return }
        isAILoading = true
        
        let context = AISessionService.buildSessionContext(
            from: sessionStore.sessions,
            currency: settingsStore.settings.currency
        )
        
        let recentMessages = Array(chatMessages.suffix(6))
        
        do {
            let result = try await AISessionService.shared.converse(
                messages: recentMessages,
                conversationId: conversationId,
                workerBaseURL: settingsStore.settings.workerBaseURL,
                geminiKey: settingsStore.settings.geminiAPIKey ?? APIKeysLoader.geminiKey,
                openAIKey: settingsStore.settings.openAIAPIKey ?? APIKeysLoader.openAIKey,
                existingSessions: context
            )
            
            guard !Task.isCancelled else { return }
            switch result {
            case .followUp(let question):
                guard !Task.isCancelled else { return }
                withAnimation(AppTheme.smoothSpring) {
                    chatMessages.append(ChatMessage(role: .assistant, text: question))
                }
                
            case .complete(let parsed):
                handleComplete(parsed, usedOfflineParser: false)
            case .completeOffline(let parsed):
                handleComplete(parsed, usedOfflineParser: true)
                
            case .update(let sessionNumber, let fields):
                guard !Task.isCancelled else { return }
                if var existing = sessionStore.session(byNumber: sessionNumber) {
                    if !subscriptionStore.isSubscribed {
                        AISessionCrafterUsage.consumeOne()
                    }
                    existing = AISessionService.applyUpdate(to: existing, fields: fields)
                    sessionStore.updateSession(existing)
                    
                    let updatedNumber = sessionStore.displayNumber(for: existing) ?? sessionNumber
                    let fieldNames = fields.keys.sorted().joined(separator: ", ")
                    withAnimation(AppTheme.smoothSpring) {
                        chatMessages.append(ChatMessage(
                            role: .assistant,
                            text: "Session #\(updatedNumber) updated",
                            card: .session(
                                ChatMessage.SessionCard(
                                    sessionID: existing.id,
                                    headline: "Session #\(updatedNumber) updated",
                                    detail: fieldNames.isEmpty ? nil : "Changed: \(fieldNames)",
                                    systemImage: "checkmark.circle.fill"
                                )
                            )
                        ))
                    }
                    if settingsStore.settings.hapticFeedback { HapticManager.success() }
                } else {
                    withAnimation(AppTheme.smoothSpring) {
                        chatMessages.append(ChatMessage(
                            role: .assistant,
                            text: "I couldn't find session #\(sessionNumber). Check the Sessions tab for valid session numbers."
                        ))
                    }
                }
            }
        } catch let err as AISessionError where err.isFriendly {
            guard !Task.isCancelled else { return }
            withAnimation(AppTheme.smoothSpring) {
                chatMessages.append(ChatMessage(role: .assistant, text: err.errorDescription ?? "Something went wrong."))
            }
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        } catch is URLError {
            guard !Task.isCancelled else { return }
            withAnimation(AppTheme.smoothSpring) {
                chatMessages.append(ChatMessage(role: .assistant, text: "Couldn't reach the AI service. Check your connection and try again."))
            }
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        } catch {
            guard !Task.isCancelled else { return }
            aiError = error.localizedDescription
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        }
    }
    
    @MainActor
    private func handleComplete(_ parsed: ParsedSession, usedOfflineParser: Bool) {
        guard AISessionService.isLoggable(parsed) else {
            withAnimation(AppTheme.smoothSpring) {
                chatMessages.append(ChatMessage(
                    role: .assistant,
                    text: AISessionService.minimumInfoFollowUpMessage()
                ))
            }
            return
        }
        if !usedOfflineParser, !subscriptionStore.isSubscribed {
            AISessionCrafterUsage.consumeOne()
        }
        let effectiveAmount: Double
        let isTournament = parsed.gameType == .tournament || parsed.gameType == .sitAndGo
        if isTournament, let buyIn = parsed.buyIn, let cashOut = parsed.cashOut {
            let effectiveBuyins = max(1, parsed.buyins ?? 1)
            effectiveAmount = cashOut - (buyIn * Double(effectiveBuyins))
        } else {
            effectiveAmount = parsed.amount
        }
        let session = PokerSession(
            amount: effectiveAmount,
            date: parsed.date ?? Date(),
            notes: parsed.notes ?? "",
            gameType: parsed.gameType,
            variant: parsed.variant,
            hoursPlayed: parsed.hoursPlayed,
            stakes: parsed.stakes,
            venue: parsed.venue,
            rake: parsed.rake,
            tips: parsed.tips,
            food: parsed.food,
            travel: parsed.travel,
            fees: parsed.fees,
            buyIn: parsed.buyIn,
            cashOut: parsed.cashOut,
            tournamentPosition: parsed.tournamentPosition,
            buyins: parsed.buyins,
            handNotes: parsed.handNotes,
            tags: parsed.tags
        )
        sessionStore.addSession(session)
        let num = sessionStore.displayNumber(for: session)
        let loggedText = num.map { "Session #\($0) logged" } ?? "Session logged"
        let detail = usedOfflineParser ? "Parsed offline because the AI service was unavailable." : nil
        withAnimation(AppTheme.smoothSpring) {
            chatMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: loggedText,
                    card: .session(
                        ChatMessage.SessionCard(
                            sessionID: session.id,
                            headline: loggedText,
                            detail: detail,
                            systemImage: "sparkles"
                        )
                    )
                )
            )
        }
        if settingsStore.settings.hapticFeedback { HapticManager.success() }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isAnimating ? 1 : 0.72)
                    .opacity(isAnimating ? 1 : 0.4)
                    .offset(y: isAnimating ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .onAppear {
            isAnimating = true
        }
    }
}

private struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
            .environmentObject(SubscriptionStore.shared)
    }
}
