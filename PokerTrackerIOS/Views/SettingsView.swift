//
//  SettingsView.swift
//  PokerTrackerIOS
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum FocusField: Hashable {
        case geminiAPIKey
        case openAIAPIKey
        case newQuickVenue
        case startingBankroll
        case defaultStakes
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var showingExportSheet = false
    @State private var exportData: String = ""
    @State private var showingRestoreImporter = false
    @State private var showingRestoreConfirm = false
    @State private var pendingRestoreData: Data?
    @State private var showingBackupExporter = false
    @State private var backupDocument = TextFileDocument(text: "")
    @State private var showingRestoreResult = false
    @State private var restoreResultTitle = "Restore"
    @State private var restoreResultMessage = ""
    @State private var showingPaywall = false
    @State private var newQuickVenue = ""
    @FocusState private var focusedField: FocusField?

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty && version != build:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "Unknown"
        }
    }

    private var selectedVariantText: String {
        settingsStore.settings.defaultVariant ?? PokerVariant.noLimitHoldem.rawValue
    }

    private var selectedCurrencyText: String {
        let code = settingsStore.settings.currency
        return "\(code) · \(SupportedCurrency.symbol(for: code))"
    }

    private var startingBankrollText: String {
        settingsStore.settings.displayUnsignedAmount(settingsStore.settings.startingBankroll)
    }

    private var activeStakesPresetCount: Int {
        StakesPreset.enabledPresets(from: settingsStore.settings.enabledStakesPresets).count
    }

    private var trackerDefaultsText: String {
        var parts = [settingsStore.settings.defaultGameType.rawValue, selectedVariantText]
        if let defaultStakes = normalizedText(settingsStore.settings.defaultStakes) {
            parts.append(defaultStakes)
        }
        return parts.joined(separator: " • ")
    }

    private var quickButtonsText: String {
        "\(activeStakesPresetCount) stakes • \(venueQuickOptions.count) venues"
    }

    private var aiModeText: String {
        let hasGemini = normalizedText(settingsStore.settings.geminiAPIKey) != nil
        let hasOpenAI = normalizedText(settingsStore.settings.openAIAPIKey) != nil

        switch (hasGemini, hasOpenAI) {
        case (true, true):
            return "Gemini + OpenAI"
        case (true, false):
            return "Gemini"
        case (false, true):
            return "OpenAI"
        case (false, false):
            return "Built-in"
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    settingsOverviewCard
                    trackerSetupSection
                    quickButtonsSection
                    premiumAndAISection
                    appearanceAndBehaviorSection
                    dataAndSafetySection
                    helpAndSupportSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportSheet(data: exportData)
            }
            .fileImporter(
                isPresented: $showingRestoreImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleRestoreImport(result)
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "poker-sessions-backup"
            ) { result in
                switch result {
                case .success:
                    restoreResultTitle = "Backup Complete"
                    restoreResultMessage = "Backup file exported successfully."
                    showingRestoreResult = true
                case .failure(let error):
                    guard !isUserCancellation(error) else { return }
                    restoreResultTitle = "Backup Failed"
                    restoreResultMessage = error.localizedDescription
                    showingRestoreResult = true
                }
            }
            .alert("Replace Current Sessions?", isPresented: $showingRestoreConfirm) {
                Button("Cancel", role: .cancel) {
                    pendingRestoreData = nil
                }
                Button("Replace", role: .destructive) {
                    performRestore()
                }
            } message: {
                Text("This will replace all existing sessions with the backup file.")
            }
            .alert(restoreResultTitle, isPresented: $showingRestoreResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreResultMessage)
            }
        }
    }

    private var settingsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up Your Tracker")
                        .font(.title3.weight(.bold))
                    Text("Make new sessions faster to log, keep results readable, and protect your data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill((subscriptionStore.isSubscribed ? Color.yellow : AppTheme.accent).opacity(subscriptionStore.isSubscribed ? 0.18 : 0.10))
                            .frame(width: 52, height: 52)
                        Image(systemName: subscriptionStore.isSubscribed ? "crown.fill" : "slider.horizontal.3")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(subscriptionStore.isSubscribed ? Color.yellow : AppTheme.accent)
                    }

                    settingsInfoBadge(
                        subscriptionStore.isSubscribed ? "Premium" : "Standard",
                        tint: subscriptionStore.isSubscribed ? .green : AppTheme.accent,
                        fill: subscriptionStore.isSubscribed ? Color.green.opacity(0.14) : AppTheme.accent.opacity(0.12)
                    )
                }
            }

            settingsHighlightRow(
                title: "New Session Defaults",
                value: trackerDefaultsText,
                systemImage: "wand.and.stars",
                tint: AppTheme.accent
            )

            settingsHighlightRow(
                title: "Quick Buttons",
                value: quickButtonsText,
                systemImage: "square.grid.2x2",
                tint: .teal
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                overviewMetricTile(title: "Starting Roll", value: startingBankrollText)
                overviewMetricTile(title: "AI Mode", value: aiModeText)
                overviewMetricTile(title: "Sessions", value: "\(sessionStore.sessions.count)")
                overviewMetricTile(title: "Currency", value: settingsStore.settings.currency)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.cardBackground,
                            AppTheme.cardBackground,
                            AppTheme.accent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppTheme.subtleShadow.color, radius: AppTheme.subtleShadow.radius, y: AppTheme.subtleShadow.y)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.08), lineWidth: 1)
        )
    }

    private var trackerSetupSection: some View {
        settingsSection(
            title: "Tracker Setup",
            subtitle: "Set your money context and the defaults the logger should start with.",
            systemImage: "slider.horizontal.3",
            tint: AppTheme.accent,
            badge: settingsStore.settings.currency
        ) {
            settingsMenuRow(
                title: "Display Currency",
                subtitle: "Used for bankroll totals, hourly rates, exports, and stake presets",
                value: selectedCurrencyText
            ) {
                ForEach(SupportedCurrency.all) { currency in
                    Button(currency.pickerLabel) {
                        updateCurrency(to: currency.code)
                    }
                }
            }

            settingsDivider

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Starting Bankroll")
                        .font(.body.weight(.medium))
                    Text("Sets the opening balance used in your overall bankroll total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TextField("0", value: startingBankrollBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .startingBankroll)
                    .frame(width: 140)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(UIColor.systemBackground))
                    )
            }
            .padding(16)

            settingsDivider

            settingsMenuRow(
                title: "Default Format",
                subtitle: "The game format pre-selected when you log a session",
                value: settingsStore.settings.defaultGameType.rawValue
            ) {
                ForEach(GameType.formatOptions, id: \.self) { gameType in
                    Button(gameType.rawValue) {
                        settingBinding(\.defaultGameType).wrappedValue = gameType
                    }
                }
            }

            settingsDivider

            settingsMenuRow(
                title: "Default Variant",
                subtitle: "The poker variant you use most often",
                value: selectedVariantText
            ) {
                ForEach(PokerVariant.allCases, id: \.rawValue) { variant in
                    Button(variant.rawValue) {
                        defaultVariantBinding.wrappedValue = variant.rawValue
                    }
                }
            }

            settingsDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("Default Stakes")
                    .font(.body.weight(.medium))

                Text("Optional fallback used when a new session does not already inherit stakes from a recent session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("Optional", text: defaultStakesBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .defaultStakes)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(UIColor.systemBackground))
                        )

                    if normalizedText(settingsStore.settings.defaultStakes) != nil {
                        Button {
                            defaultStakesBinding.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                FlowLayout(spacing: 8) {
                    settingsSelectionChip(
                        title: "None",
                        isSelected: normalizedText(settingsStore.settings.defaultStakes) == nil,
                        tint: .gray
                    ) {
                        defaultStakesBinding.wrappedValue = ""
                    }

                    ForEach(StakesPreset.allCases, id: \.self) { preset in
                        settingsSelectionChip(
                            title: preset.rawValue,
                            isSelected: defaultStakesMatches(preset),
                            tint: AppTheme.accent
                        ) {
                            defaultStakesBinding.wrappedValue = preset.storedValue(currency: settingsStore.settings.currency)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
    }

    private var quickButtonsSection: some View {
        settingsSection(
            title: "Quick Buttons",
            subtitle: "Choose which one-tap stakes and venue buttons appear in the session logger.",
            systemImage: "square.grid.2x2",
            tint: .teal,
            badge: "\(activeStakesPresetCount + venueQuickOptions.count) active"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                settingsSubsectionHeader(title: "Stake Buttons", detail: "\(activeStakesPresetCount) enabled")

                Text(loggerQuickStakesFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                FlowLayout(spacing: 8) {
                    ForEach(StakesPreset.allCases, id: \.self) { preset in
                        settingsSelectionChip(
                            title: preset.rawValue,
                            isSelected: stakesPresetBinding(for: preset).wrappedValue,
                            tint: .teal
                        ) {
                            let binding = stakesPresetBinding(for: preset)
                            binding.wrappedValue.toggle()
                        }
                    }
                }
                .padding(16)

                settingsDivider

                settingsSubsectionHeader(
                    title: "Venue Buttons",
                    detail: venueQuickOptions.isEmpty ? "None yet" : "\(venueQuickOptions.count) active"
                )

                Text("Venues become quick buttons automatically after \(SessionStore.automaticVenueQuickOptionThreshold)+ logged sessions. Manually pinned venues stay until you remove them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    TextField("Add venue button", text: $newQuickVenue)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .newQuickVenue)
                        .onSubmit {
                            addQuickVenue(newQuickVenue)
                        }

                    Button {
                        addQuickVenue(newQuickVenue)
                    } label: {
                        Text("Add")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(cleanedNewQuickVenue == nil ? Color.secondary : Color.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(cleanedNewQuickVenue == nil ? Color(UIColor.systemGray5) : AppTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(cleanedNewQuickVenue == nil)
                }
                .padding(16)

                if !addableQuickVenues.isEmpty {
                    settingsDivider

                    Menu {
                        ForEach(addableQuickVenues, id: \.self) { venue in
                            Button(venue) {
                                addQuickVenue(venue)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.teal)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add Logged Venue")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("Choose from venues already found in your session history")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }

                settingsDivider

                if venueQuickOptions.isEmpty {
                    Text("No venue quick buttons yet. Add one manually or log a few sessions at the same room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(venueQuickOptions.enumerated()), id: \.element.id) { index, option in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.venue)
                                    .font(.body.weight(.medium))
                                Text(venueQuickOptionDetail(option))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            settingsInfoBadge(
                                option.source == .manual ? "Pinned" : "Auto",
                                tint: option.source == .manual ? AppTheme.accent : .teal,
                                fill: option.source == .manual ? AppTheme.accent.opacity(0.12) : Color.teal.opacity(0.12)
                            )

                            Button {
                                removeQuickVenue(option.venue)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(option.venue)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < venueQuickOptions.count - 1 {
                            settingsDivider
                        }
                    }
                }
            }
        }
    }

    private var premiumAndAISection: some View {
        settingsSection(
            title: "Premium & AI",
            subtitle: subscriptionStore.isSubscribed
                ? "Premium features are unlocked. Personal API keys are optional."
                : "Track your free usage, unlock unlimited tools, or connect your own AI keys.",
            systemImage: "sparkles",
            tint: .orange,
            badge: subscriptionStore.isSubscribed ? "Unlocked" : "Standard"
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((subscriptionStore.isSubscribed ? Color.yellow : .orange).opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(subscriptionStore.isSubscribed ? Color.yellow : Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscriptionStore.isSubscribed ? "Premium is active" : "Premium unlocks every limit")
                            .font(.body.weight(.semibold))
                        Text(
                            subscriptionStore.isSubscribed
                            ? "Unlimited AI logging, odds calculations, and charts are available on this device."
                            : (subscriptionStore.subscriptionDisplayPrice.map { "\($0). Upgrade for unlimited AI logging, odds calculations, and all charts." }
                                ?? "Upgrade for unlimited AI logging, odds calculations, and all charts.")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    if subscriptionStore.isSubscribed {
                        settingsInfoBadge("Active", tint: .green, fill: Color.green.opacity(0.14))
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            Text("View Plans")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule(style: .continuous).fill(AppTheme.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)

                settingsDivider

                HStack(spacing: 12) {
                    usageTile(
                        title: "AI Session Crafter",
                        value: subscriptionStore.isSubscribed ? "Unlimited" : "\(AISessionCrafterUsage.usesRemaining)",
                        subtitle: subscriptionStore.isSubscribed ? "Premium active" : "of \(AISessionCrafterUsage.freeUseLimit) free uses left",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        tint: AppTheme.accent
                    )

                    usageTile(
                        title: "Odds Calculator",
                        value: subscriptionStore.isSubscribed ? "Unlimited" : "\(OddsCalculatorUsage.usesRemaining)",
                        subtitle: subscriptionStore.isSubscribed ? "Premium active" : "of \(OddsCalculatorUsage.freeUseLimit) free uses left",
                        systemImage: "percent",
                        tint: .orange
                    )
                }
                .padding(16)

                settingsDivider

                settingsFieldRow(
                    title: "Gemini API Key",
                    subtitle: "Used first when present. Leave blank to keep the built-in path."
                ) {
                    SecureField("Paste Gemini key", text: optionalStringBinding(\.geminiAPIKey))
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .geminiAPIKey)
                }

                settingsDivider

                settingsFieldRow(
                    title: "OpenAI API Key",
                    subtitle: "Optional fallback if you want a second provider available."
                ) {
                    SecureField("Paste OpenAI key", text: optionalStringBinding(\.openAIAPIKey))
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .openAIAPIKey)
                }
            }
        }
    }

    private var appearanceAndBehaviorSection: some View {
        settingsSection(
            title: "Appearance & Behavior",
            subtitle: "Control how information looks and how the app responds day to day.",
            systemImage: "paintbrush.pointed",
            tint: .indigo
        ) {
            settingsMenuRow(
                title: "Win / Loss Colors",
                subtitle: "Includes colorblind-friendly alternatives",
                value: settingsStore.settings.profitLossColorScheme.rawValue
            ) {
                ForEach(ProfitLossColorScheme.allCases, id: \.self) { scheme in
                    Button(scheme.rawValue) {
                        settingBinding(\.profitLossColorScheme).wrappedValue = scheme
                    }
                }
            }

            settingsDivider

            settingsToggleRow(
                title: "Show Hourly Rate",
                subtitle: "Display hourly results when enough session time exists",
                isOn: settingBinding(\.showHourlyRate)
            )

            settingsDivider

            settingsToggleRow(
                title: "Show Session Numbers",
                subtitle: "Display numbered session badges around the app",
                isOn: settingBinding(\.showSessionNumbers)
            )

            settingsDivider

            settingsToggleRow(
                title: "Compact Currency",
                subtitle: "Shorten large values to formats like $1.2K",
                isOn: settingBinding(\.useCompactCurrency)
            )

            settingsDivider

            settingsToggleRow(
                title: "24-Hour Time",
                subtitle: "Show times like 18:30 instead of 6:30 PM",
                isOn: settingBinding(\.use24HourTime)
            )

            settingsDivider

            settingsToggleRow(
                title: "Haptic Feedback",
                subtitle: "Use light tactile confirmation for key actions",
                isOn: settingBinding(\.hapticFeedback)
            )

            settingsDivider

            settingsToggleRow(
                title: "Session Reminders",
                subtitle: "Allow the app to remind you to log sessions consistently",
                isOn: settingBinding(\.reminderEnabled)
            )
        }
    }

    private var dataAndSafetySection: some View {
        settingsSection(
            title: "Data & Safety",
            subtitle: "Back up sessions, export data, and guard destructive actions.",
            systemImage: "externaldrive",
            tint: .green
        ) {
            settingsToggleRow(
                title: "Confirm Before Delete",
                subtitle: "Require confirmation before removing a session",
                isOn: settingBinding(\.confirmBeforeDelete)
            )

            settingsDivider

            settingsActionRow(
                title: "Export to CSV",
                subtitle: "Share a spreadsheet-friendly version of your sessions",
                systemImage: "square.and.arrow.up",
                tint: AppTheme.accent
            ) {
                exportData = sessionStore.exportCSV(currency: settingsStore.settings.currency)
                showingExportSheet = true
            }

            settingsDivider

            settingsActionRow(
                title: "Backup Sessions (JSON)",
                subtitle: "Create a full backup file of your session history",
                systemImage: "externaldrive.badge.plus",
                tint: .green
            ) {
                if let backup = sessionStore.exportBackupJSON() {
                    backupDocument = TextFileDocument(text: backup)
                    showingBackupExporter = true
                } else {
                    restoreResultTitle = "Backup Failed"
                    restoreResultMessage = "Could not generate backup data."
                    showingRestoreResult = true
                }
            }

            settingsDivider

            settingsActionRow(
                title: "Restore Sessions (JSON)",
                subtitle: "Replace current sessions with a previous backup",
                systemImage: "arrow.clockwise.circle",
                tint: .orange
            ) {
                showingRestoreImporter = true
            }
        }
    }

    private var helpAndSupportSection: some View {
        settingsSection(
            title: "Help & Support",
            subtitle: "Version information, privacy details, and support links.",
            systemImage: "questionmark.circle",
            tint: .gray
        ) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Version")
                        .font(.body.weight(.medium))
                    Text("Current release installed on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                settingsInfoBadge(appVersionText, tint: AppTheme.secondaryText, fill: Color.primary.opacity(0.06))
            }
            .padding(16)

            settingsDivider

            settingsLinkRow(
                title: "Privacy Policy",
                subtitle: "See how data is handled and protected",
                systemImage: "hand.raised",
                tint: AppTheme.accent,
                destination: AppURLs.privacyPolicy
            )

            settingsDivider

            settingsLinkRow(
                title: "Support",
                subtitle: "Get help or send feedback",
                systemImage: "questionmark.bubble",
                tint: AppTheme.accent,
                destination: AppURLs.support
            )
        }
    }

    private func handleRestoreImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            pendingRestoreData = nil
            guard !isUserCancellation(error) else { return }
            restoreResultTitle = "Restore Failed"
            restoreResultMessage = error.localizedDescription
            showingRestoreResult = true
        case .success(let urls):
            pendingRestoreData = nil
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                pendingRestoreData = data
                showingRestoreConfirm = true
            } catch {
                pendingRestoreData = nil
                restoreResultTitle = "Restore Failed"
                restoreResultMessage = error.localizedDescription
                showingRestoreResult = true
            }
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func performRestore() {
        guard let data = pendingRestoreData else { return }
        pendingRestoreData = nil
        do {
            let count = try sessionStore.restoreFromBackupJSON(data)
            restoreResultTitle = "Restore Complete"
            restoreResultMessage = "Restored \(count) session\(count == 1 ? "" : "s")."
            if settingsStore.settings.hapticFeedback { HapticManager.success() }
        } catch {
            restoreResultTitle = "Restore Failed"
            restoreResultMessage = error.localizedDescription
            if settingsStore.settings.hapticFeedback { HapticManager.notification(.error) }
        }
        showingRestoreResult = true
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<AppSettings, String?>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] ?? "" },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value.isEmpty ? nil : value }
            }
        )
    }

    private var defaultVariantBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultVariant ?? PokerVariant.noLimitHoldem.rawValue },
            set: { value in
                settingsStore.update { $0.defaultVariant = value }
            }
        )
    }

    private var startingBankrollBinding: Binding<Double?> {
        Binding(
            get: {
                let bankroll = settingsStore.settings.startingBankroll
                return bankroll == 0 ? nil : bankroll
            },
            set: { value in
                settingsStore.update { $0.startingBankroll = value ?? 0 }
            }
        )
    }

    private var defaultStakesBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultStakes ?? "" },
            set: { value in
                settingsStore.update {
                    $0.defaultStakes = normalizedText(value)
                }
            }
        )
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func defaultStakesMatches(_ preset: StakesPreset) -> Bool {
        guard let current = normalizedText(settingsStore.settings.defaultStakes) else { return false }
        return current == preset.rawValue || current == preset.storedValue(currency: settingsStore.settings.currency)
    }

    private func updateCurrency(to newCurrency: String) {
        let oldCurrency = settingsStore.settings.currency
        settingsStore.update { settings in
            if let currentDefaultStakes = normalizedText(settings.defaultStakes),
               let preset = StakesPreset.allCases.first(where: {
                   currentDefaultStakes == $0.rawValue || currentDefaultStakes == $0.storedValue(currency: oldCurrency)
               }) {
                settings.defaultStakes = preset.storedValue(currency: newCurrency)
            }
            settings.currency = newCurrency
        }
    }

    private var venueQuickOptions: [VenueQuickOption] {
        sessionStore.venueQuickOptions(using: settingsStore.settings)
    }

    private var addableQuickVenues: [String] {
        let activeKeys = Set(venueQuickOptions.compactMap { VenueCleaner.key(for: $0.venue) })
        return sessionStore.availableVenues.filter { venue in
            guard let key = VenueCleaner.key(for: venue) else { return false }
            return !activeKeys.contains(key)
        }
    }

    private var cleanedNewQuickVenue: String? {
        VenueCleaner.clean(newQuickVenue)
    }

    private var loggerQuickStakesFooterText: String {
        let enabled = StakesPreset.enabledPresets(from: settingsStore.settings.enabledStakesPresets)
        if enabled.isEmpty {
            return "No stake quick buttons will appear in the session logger. Manual stake entry still works."
        }
        return "Choose which quick stake buttons appear in the session logger."
    }

    private func stakesPresetBinding(for preset: StakesPreset) -> Binding<Bool> {
        Binding(
            get: {
                settingsStore.settings.enabledStakesPresets.contains(preset.rawValue)
            },
            set: { isEnabled in
                settingsStore.update { settings in
                    var enabled = Set(settings.enabledStakesPresets)
                    if isEnabled {
                        enabled.insert(preset.rawValue)
                    } else {
                        enabled.remove(preset.rawValue)
                    }
                    settings.enabledStakesPresets = StakesPreset.normalizedRawValues(Array(enabled))
                }
            }
        )
    }

    private func venueQuickOptionDetail(_ option: VenueQuickOption) -> String {
        switch option.source {
        case .manual:
            return "Pinned manually"
        case .automatic(let sessionCount):
            return "Automatic from \(sessionCount) session\(sessionCount == 1 ? "" : "s")"
        }
    }

    private func addQuickVenue(_ venue: String) {
        guard let cleaned = VenueCleaner.clean(venue) else { return }
        newQuickVenue = ""

        settingsStore.update { settings in
            var pinned = settings.pinnedVenueOptions
            pinned.append(cleaned)
            settings.pinnedVenueOptions = AppSettings.normalizedVenueOptions(pinned)
            settings.hiddenVenueOptions = AppSettings.normalizedVenueOptions(
                settings.hiddenVenueOptions.filter {
                    VenueCleaner.key(for: $0) != VenueCleaner.key(for: cleaned)
                }
            )
        }
    }

    private func removeQuickVenue(_ venue: String) {
        guard let key = VenueCleaner.key(for: venue) else { return }

        settingsStore.update { settings in
            settings.pinnedVenueOptions = AppSettings.normalizedVenueOptions(
                settings.pinnedVenueOptions.filter {
                    VenueCleaner.key(for: $0) != key
                }
            )

            var hidden = settings.hiddenVenueOptions
            hidden.append(venue)
            settings.hiddenVenueOptions = AppSettings.normalizedVenueOptions(hidden)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accent,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionHeader(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint,
                badge: badge
            )
            settingsCard {
                content()
            }
        }
    }

    private func settingsSectionHeader(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accent,
        badge: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let badge {
                settingsInfoBadge(badge, tint: tint, fill: tint.opacity(0.12))
            }
        }
        .padding(.horizontal, 4)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: AppTheme.subtleShadow.color, radius: AppTheme.subtleShadow.radius, y: AppTheme.subtleShadow.y)
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 16)
    }

    private func overviewMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .kerning(0.6)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.systemBackground).opacity(0.7))
        )
    }

    private func settingsFieldRow<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder field: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.medium))

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            field()
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.systemBackground))
                )
        }
        .padding(16)
    }

    private func settingsMenuRow<MenuItems: View>(
        title: String,
        subtitle: String? = nil,
        value: String,
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        Menu {
            menuItems()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(UIColor.systemBackground))
                )
            }
            .contentShape(Rectangle())
            .padding(16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Opens options")
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(AppTheme.accent)
        .padding(16)
    }

    private func settingsActionRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    private func settingsLinkRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    private func settingsInfoBadge(_ text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
    }

    private func settingsHighlightRow(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.systemBackground).opacity(0.72))
        )
    }

    private func settingsSubsectionHeader(title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            settingsInfoBadge(detail, tint: AppTheme.secondaryText, fill: Color.primary.opacity(0.06))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func settingsSelectionChip(
        title: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint : Color(UIColor.systemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.2) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func usageTile(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.systemBackground))
        )
    }
}

struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let decoded = String(data: data, encoding: .utf8) {
            text = decoded
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: String
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(data)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Export Data")
                        .font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: data, subject: Text("Poker Sessions Export"), message: Text("My poker session data")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
            .environmentObject(SubscriptionStore.shared)
    }
}
