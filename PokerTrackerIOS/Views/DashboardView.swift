//
//  DashboardView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingAddSession = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isAILoading = false
    @State private var aiError: String?
    @FocusState private var inputFocused: Bool
    
    private var bankroll: Double {
        settingsStore.settings.startingBankroll + sessionStore.totalProfit
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statsHeader
                
                Divider()
                
                chatArea
                
                inputBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .navigationTitle("Poker Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Poker Tracker")
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSession = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView()
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("Bankroll")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(PokerSession.formatCurrency(bankroll, currency: settingsStore.settings.currency))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(bankroll >= 0 ? settingsStore.settings.profitLossColorScheme.winColor : settingsStore.settings.profitLossColorScheme.lossColor)
            }
            
            HStack(spacing: 0) {
                statItem("\(sessionStore.totalSessions)", "Sessions")
                Divider().frame(height: 24)
                statItem(String(format: "%.0f%%", sessionStore.winRate), "Win Rate")
                Divider().frame(height: 24)
                statItem("\(sessionStore.winCount)/\(sessionStore.lossCount)", "W/L")
                if sessionStore.totalHoursPlayed > 0, let rate = sessionStore.hourlyRate {
                    Divider().frame(height: 24)
                    statItem(PokerSession.formatCurrency(rate, currency: settingsStore.settings.currency), "$/hr")
                }
            }
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground)
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
    
    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Chat Area
    
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if chatMessages.isEmpty {
                    emptyPrompt
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Make tapping the empty area immediately focus the input
                            inputFocused = true
                        }
                } else {
                    LazyVStack(spacing: 8) {
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Log a session or update an existing one")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try: \"Won $200 at 1/2 NLH\" or \"Update session #3 stakes to 2/5\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(message.role == .user ? Color.blue : AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            
            Divider()
            
            HStack(spacing: 10) {
                if !chatMessages.isEmpty {
                    Button {
                        withAnimation(AppTheme.smoothSpring) {
                            chatMessages.removeAll()
                            aiError = nil
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Dismiss button when keyboard is focused
                if inputFocused {
                    Button {
                        inputFocused = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                
                TextField("Log a session...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(20)
                    .focused($inputFocused)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty || isAILoading
                            ? Color.gray : AppTheme.accent
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isAILoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Send & AI Logic
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        withAnimation(AppTheme.smoothSpring) {
            chatMessages.append(ChatMessage(role: .user, text: text))
        }
        inputText = ""
        aiError = nil
        
        Task { await processWithAI() }
    }
    
    private func processWithAI() async {
        isAILoading = true
        
        let context = AISessionService.buildSessionContext(
            from: sessionStore.sessions,
            currency: settingsStore.settings.currency
        )
        
        do {
            let result = try await AISessionService.shared.converse(
                messages: chatMessages,
                geminiKey: settingsStore.settings.geminiAPIKey ?? APIKeysLoader.geminiKey,
                openAIKey: settingsStore.settings.openAIAPIKey ?? APIKeysLoader.openAIKey,
                existingSessions: context
            )
            
            switch result {
            case .followUp(let question):
                withAnimation(AppTheme.smoothSpring) {
                    chatMessages.append(ChatMessage(role: .assistant, text: question))
                }
                
            case .complete(let parsed):
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
                    handNotes: parsed.handNotes
                )
                sessionStore.addSession(session)
                
                let num = sessionStore.displayNumber(for: session) ?? 0
                let summary = buildSummary(parsed, sessionNumber: num)
                withAnimation(AppTheme.smoothSpring) {
                    chatMessages.append(ChatMessage(role: .assistant, text: summary))
                }
                if settingsStore.settings.hapticFeedback { HapticManager.success() }
                
            case .update(let sessionNumber, let fields):
                if var existing = sessionStore.session(byNumber: sessionNumber) {
                    existing = AISessionService.applyUpdate(to: existing, fields: fields)
                    sessionStore.updateSession(existing)
                    
                    let fieldNames = fields.keys.joined(separator: ", ")
                    withAnimation(AppTheme.smoothSpring) {
                        chatMessages.append(ChatMessage(
                            role: .assistant,
                            text: "Updated session #\(sessionNumber) (\(fieldNames))."
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
        } catch {
            aiError = error.localizedDescription
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        }
        
        isAILoading = false
    }
    
    private func buildSummary(_ p: ParsedSession, sessionNumber: Int) -> String {
        var parts: [String] = []
        parts.append("Session #\(sessionNumber) logged!")
        let amtStr = p.amount >= 0
            ? PokerSession.formatCurrency(p.amount, currency: settingsStore.settings.currency)
            : PokerSession.formatCurrency(abs(p.amount), currency: settingsStore.settings.currency)
        parts.append(p.amount >= 0 ? "Won \(amtStr)" : "Lost \(amtStr)")
        if let s = p.stakes { parts.append(s) }
        let variantStr = p.variant ?? p.gameType.rawValue
        parts.append(PokerSession.abbreviation(for: variantStr))
        if let v = p.venue { parts.append("at \(v)") }
        if let h = p.hoursPlayed { parts.append("\(String(format: "%.1f", h))h") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .offset(y: phase == Double(i) ? -4 : 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                phase = 2
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
}
