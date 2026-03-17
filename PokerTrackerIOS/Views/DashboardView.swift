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

    private var allSessionsProfit: Double {
        allSessions.reduce(0) { $0 + $1.amount }
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
                    value: PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency),
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
            .navigationTitle("Poker Bankroll AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Poker Bankroll AI")
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSession = true } label: {
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
    
    private var statsHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bankroll")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Text(PokerSession.formatCurrency(bankroll, currency: settingsStore.settings.currency))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(bankroll >= 0 ? winColor : lossColor)
                        .contentTransition(.numericText())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dashboardMetrics) { metric in
                            metricChip(metric)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: AppTheme.subtleShadow.color, radius: AppTheme.subtleShadow.radius, y: AppTheme.subtleShadow.y)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .padding(.horizontal)
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func metricChip(_ metric: DashboardMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            Text(metric.value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(metric.tint)
                .monospacedDigit()
        }
        .frame(minWidth: 74, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(metric.tint.opacity(0.14), lineWidth: 1)
        )
    }
    
    // MARK: - Chat Area
    
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if chatMessages.isEmpty {
                    emptyPrompt
                        .contentShape(Rectangle())
                        .onTapGesture {
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
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.accent.opacity(0.5))
                }

                Text("Log a Session")
                    .font(.title3.weight(.semibold))

                Text("Describe your session and AI will log it.\nTry \"Won $200 at 1/2 NLH for 4 hours\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                : AnyShapeStyle(AppTheme.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(message.role == .user ? 0.08 : 0.04), radius: 3, y: 1)
    }

    private func assistantSessionCard(_ payload: ChatMessage.SessionCard, session: PokerSession) -> some View {
        let sessionTint: Color = {
            if session.isWin { return winColor }
            if session.isLoss { return lossColor }
            return .secondary
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Label(payload.headline, systemImage: payload.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button {
                    chatEditSession = sessionStore.sessions.first(where: { $0.id == session.id }) ?? session
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppTheme.accent)
            }

            Text(PokerSession.formatCurrency(session.amount, currency: settingsStore.settings.currency))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(sessionTint)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 6) {
                Text(sessionCardPrimaryMeta(session))
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if let venue = session.venue, !venue.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                        Text(venue)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let detail = payload.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(sessionTint.opacity(0.12), lineWidth: 1)
        )
    }

    private func sessionCardPrimaryMeta(_ session: PokerSession) -> String {
        var parts = [session.displayVariantAbbreviation, session.gameType.abbreviation]
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
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if !subscriptionStore.isSubscribed && AISessionCrafterUsage.usesRemaining < AISessionCrafterUsage.freeUseLimit {
                HStack {
                    Text("\(AISessionCrafterUsage.usesRemaining) of \(AISessionCrafterUsage.freeUseLimit) free AI uses left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if AISessionCrafterUsage.usesRemaining == 0 {
                        Button("Unlock unlimited") { showingPaywall = true }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider()
            
            HStack(spacing: 10) {
                if !chatMessages.isEmpty {
                    Button {
                        aiTask?.cancel()
                        withAnimation(AppTheme.smoothSpring) {
                            chatMessages.removeAll()
                            conversationId = UUID().uuidString
                            aiError = nil
                            isAILoading = false
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if inputFocused {
                    Button {
                        inputFocused = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                TextField("Log a session...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )
                    .focused($inputFocused)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading
                            ? Color.gray.opacity(0.5) : AppTheme.accent
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Send & AI Logic
    
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
        if !subscriptionStore.isSubscribed {
            AISessionCrafterUsage.consumeOne()
        }
        let session = PokerSession(
            amount: parsed.amount,
            date: parsed.date ?? Date(),
            notes: parsed.notes ?? "",
            gameType: parsed.gameType,
            variant: parsed.variant,
            hoursPlayed: parsed.hoursPlayed,
            stakes: parsed.stakes,
            venue: parsed.venue,
            buyIn: parsed.buyIn,
            cashOut: parsed.cashOut,
            tournamentPosition: parsed.tournamentPosition,
            rebuys: parsed.rebuys,
            handNotes: parsed.handNotes,
            tags: parsed.tags
        )
        sessionStore.addSession(session)
        let num = sessionStore.displayNumber(for: session) ?? 0
        let detail = usedOfflineParser ? "Parsed offline because the AI service was unavailable." : nil
        withAnimation(AppTheme.smoothSpring) {
            chatMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Session #\(num) logged",
                    card: .session(
                        ChatMessage.SessionCard(
                            sessionID: session.id,
                            headline: "Session #\(num) logged",
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
