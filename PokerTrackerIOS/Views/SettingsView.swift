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
        case newCustomStakes
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
    @State private var newCustomStakes = ""
    @State private var showingCustomDefaultStakesField = false
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
            Form {
                trackerSection
                quickButtonsSection
                displaySection
                premiumAndAISection
                dataSection
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(
                    title: "Premium",
                    subtitle: "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."
                )
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
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
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
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
            .onAppear {
                showingCustomDefaultStakesField = isCustomDefaultStakes
            }
        }
    }

    // MARK: - Tracker
    @ViewBuilder
    private var trackerSection: some View {
        Section {
            Picker("Currency", selection: currencyBinding) {
                ForEach(SupportedCurrency.all) { currency in
                    Text(currency.pickerLabel).tag(currency.code)
                }
            }

            LabeledContent("Starting Bankroll") {
                TextField("0", value: startingBankrollBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .startingBankroll)
                    .frame(maxWidth: 160)
            }
        } header: {
            Text("General")
        }

        Section {
            Picker("Default Format", selection: settingBinding(\.defaultGameType)) {
                ForEach(GameType.formatOptions, id: \.self) { gameType in
                    Text(gameType.rawValue).tag(gameType)
                }
            }

            Picker("Default Variant", selection: defaultVariantBinding) {
                ForEach(PokerVariant.allCases, id: \.rawValue) { variant in
                    Text(variant.rawValue).tag(variant.rawValue)
                }
            }

            Picker("Default Stakes", selection: defaultStakesPresetSelection) {
                Text("None").tag("")
                ForEach(quickStakesList, id: \.self) { item in
                    Text(displayLabel(forQuickStake: item)).tag(storedValue(forQuickStake: item))
                }
                Text("Other…").tag("__custom__")
            }

            if showingCustomDefaultStakesField || isCustomDefaultStakes {
                TextField("Custom default stakes", text: defaultStakesBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .defaultStakes)
            }

            Toggle("Deduct Expenses by Default", isOn: settingBinding(\.deductExpensesFromProfit))
        } header: {
            Text("New Sessions")
        } footer: {
            Text("These defaults are used when you start a new session. Each session can override the expense setting in its Expenses section.")
        }
    }

    // MARK: - Quick Buttons
    @ViewBuilder
    private var quickButtonsSection: some View {
        Section {
            quickStakesContent
        } header: {
            Text("Quick Stake Buttons")
        } footer: {
            Text("Stakes appear as quick-select buttons when logging sessions. Swipe left to remove, or add your own.")
        }

        Section {
            quickVenuesContent
        } header: {
            Text("Quick Venue Buttons")
        } footer: {
            Text("Venues appear automatically after \(SessionStore.automaticVenueQuickOptionThreshold)+ sessions. Swipe left to hide a venue from quick buttons.")
        }
    }

    @ViewBuilder
    private var quickStakesContent: some View {
        Group {
            TextField("Custom stake, e.g. $1/$2 or $1/$2/$5", text: $newCustomStakes)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .newCustomStakes)
                .onSubmit { addQuickStake(newCustomStakes) }

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                addQuickStake(newCustomStakes)
            } label: {
                Label("Add Stake", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(cleanedCustomStakes == nil)

            if !quickStakesList.isEmpty {
                ForEach(quickStakesList, id: \.self) { item in
                    HStack {
                        Text(displayLabel(forQuickStake: item))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(10)
                }
                .onDelete(perform: removeQuickStake)

                if shouldShowRestoreDefaultStakes {
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        restoreDefaultStakes()
                    } label: {
                        Label("Restore Default Stakes", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No stakes added. Add one above or restore defaults.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                        restoreDefaultStakes()
                    } label: {
                        Label("Restore Default Stakes", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var quickVenuesContent: some View {
        Group {
            TextField("New venue", text: $newQuickVenue)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .newQuickVenue)
                .onSubmit { addQuickVenue(newQuickVenue) }

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                addQuickVenue(newQuickVenue)
            } label: {
                Label("Add Venue", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(cleanedNewQuickVenue == nil)

            if !addableQuickVenues.isEmpty {
                Menu {
                    ForEach(addableQuickVenues, id: \.self) { venue in
                        Button(venue) {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            addQuickVenue(venue)
                        }
                    }
                } label: {
                    Label("Add From Logged Venues", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }

            if !venueQuickOptions.isEmpty {
                ForEach(venueQuickOptions) { option in
                    Text(option.venue)
                        .font(.subheadline)
                }
                .onDelete(perform: removeQuickVenues)
            } else {
                Text("No venues pinned. Add one above or they'll appear after \(SessionStore.automaticVenueQuickOptionThreshold)+ sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Display
    @ViewBuilder
    private var displaySection: some View {
        Section {
            Picker("Win / Loss Colors", selection: settingBinding(\.profitLossColorScheme)) {
                ForEach(ProfitLossColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }

            Toggle("Show Hourly Rate", isOn: settingBinding(\.showHourlyRate))
            Toggle("Show Session Numbers", isOn: settingBinding(\.showSessionNumbers))
        } header: {
            Text("Profit & Session")
        }

        Section {
            Toggle("Compact Currency", isOn: settingBinding(\.useCompactCurrency))
            Toggle("24-Hour Time", isOn: settingBinding(\.use24HourTime))
        } header: {
            Text("Formatting")
        }

        Section {
            Toggle("Haptic Feedback", isOn: settingBinding(\.hapticFeedback))
            Toggle("Session Reminders", isOn: settingBinding(\.reminderEnabled))
            Toggle("Confirm Before Delete", isOn: settingBinding(\.confirmBeforeDelete))
        } header: {
            Text("Behavior")
        } footer: {
            Text("Controls how the app responds during daily use.")
        }
    }

    // MARK: - Premium & AI
    @ViewBuilder
    private var premiumAndAISection: some View {
        Section {
            LabeledContent("Status", value: subscriptionStore.isSubscribed ? "Active" : "Standard")

            if !subscriptionStore.isSubscribed, let price = subscriptionStore.subscriptionDisplayPrice {
                LabeledContent("Price", value: price)
            }

            LabeledContent("AI Session Crafter", value: subscriptionStore.isSubscribed ? "Unlimited" : "\(AISessionCrafterUsage.usesRemaining) of \(AISessionCrafterUsage.freeUseLimit)")
            LabeledContent("Odds Calculator", value: subscriptionStore.isSubscribed ? "Unlimited" : "\(OddsCalculatorUsage.usesRemaining) of \(OddsCalculatorUsage.freeUseLimit)")

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                showingPaywall = true
            } label: {
                Label(subscriptionStore.isSubscribed ? "Manage Premium" : "View Plans", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } header: {
            Text("Premium")
        } footer: {
            Text(subscriptionStore.isSubscribed
                 ? "Premium is active on this device."
                 : "Premium unlocks unlimited AI session logging, unlimited odds calculations, and all charts.")
        }

        Section {
            LabeledContent("Provider", value: aiModeText)

            SecureField("Gemini API Key", text: optionalStringBinding(\.geminiAPIKey))
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .geminiAPIKey)

            SecureField("OpenAI API Key", text: optionalStringBinding(\.openAIAPIKey))
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .openAIAPIKey)
        } header: {
            Text("AI")
        } footer: {
            Text("Optional. Leave blank to use the app's built-in AI.")
        }
    }

    // MARK: - Data
    private var dataSection: some View {
        Section {
            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                exportData = sessionStore.exportCSV(currency: settingsStore.settings.currency)
                showingExportSheet = true
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                if let backup = sessionStore.exportBackupJSON() {
                    backupDocument = TextFileDocument(text: backup)
                    showingBackupExporter = true
                } else {
                    restoreResultTitle = "Backup Failed"
                    restoreResultMessage = "Could not generate backup data."
                    showingRestoreResult = true
                }
            } label: {
                Label("Back Up Sessions", systemImage: "externaldrive.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }

            Button {
                if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                showingRestoreImporter = true
            } label: {
                Label("Restore From Backup", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Restoring replaces your current sessions after confirmation.")
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersionText)
            Link("Privacy Policy", destination: AppURLs.privacyPolicy)
                .contentShape(Rectangle())
            Link("Support", destination: AppURLs.support)
                .contentShape(Rectangle())
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

    private var currencyBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.currency },
            set: { newCurrency in
                updateCurrency(to: newCurrency)
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

    private var quickStakesList: [String] {
        settingsStore.settings.quickStakesList
    }

    /// True when 2+ default stakes have been deleted, or list is empty
    private var shouldShowRestoreDefaultStakes: Bool {
        let defaults = Set(AppSettings.defaultQuickStakesList)
        let current = Set(quickStakesList)
        let missingCount = defaults.subtracting(current).count
        return missingCount >= 2 || quickStakesList.isEmpty
    }

    private func displayLabel(forQuickStake item: String) -> String {
        if let preset = StakesPreset(rawValue: item) {
            return preset.rawValue
        }
        return item
    }

    private func storedValue(forQuickStake item: String) -> String {
        if let preset = StakesPreset(rawValue: item) {
            return preset.storedValue(currency: settingsStore.settings.currency)
        }
        return item
    }

    private var isCustomDefaultStakes: Bool {
        guard let current = normalizedText(settingsStore.settings.defaultStakes) else { return false }
        for item in quickStakesList {
            if defaultStakesMatchesQuickStake(item, current: current) { return false }
        }
        return true
    }

    private func defaultStakesMatchesQuickStake(_ item: String, current: String) -> Bool {
        let stored = storedValue(forQuickStake: item)
        let normalizedCurrent = AppSettings.normalizedCustomStakesValue(current) ?? current
        let normalizedStored = AppSettings.normalizedCustomStakesValue(stored) ?? stored
        return normalizedCurrent.caseInsensitiveCompare(normalizedStored) == .orderedSame
    }

    private var defaultStakesPresetSelection: Binding<String> {
        Binding(
            get: {
                guard let current = normalizedText(settingsStore.settings.defaultStakes) else {
                    return (showingCustomDefaultStakesField || isCustomDefaultStakes) ? "__custom__" : ""
                }
                for item in quickStakesList {
                    if defaultStakesMatchesQuickStake(item, current: current) {
                        return storedValue(forQuickStake: item)
                    }
                }
                return (showingCustomDefaultStakesField || isCustomDefaultStakes) ? "__custom__" : ""
            },
            set: { selection in
                switch selection {
                case "":
                    showingCustomDefaultStakesField = false
                    focusedField = nil
                    defaultStakesBinding.wrappedValue = ""
                case "__custom__":
                    showingCustomDefaultStakesField = true
                    focusedField = .defaultStakes
                default:
                    showingCustomDefaultStakesField = false
                    focusedField = nil
                    defaultStakesBinding.wrappedValue = selection
                }
            }
        )
    }

    private var cleanedCustomStakes: String? {
        AppSettings.normalizedCustomStakesValue(newCustomStakes)
    }

    private func addQuickStake(_ value: String) {
        guard let cleaned = AppSettings.normalizedCustomStakesValue(value) else { return }
        newCustomStakes = ""
        settingsStore.update { settings in
            var list = settings.quickStakesList
            if !list.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                list.append(cleaned)
                settings.quickStakesList = AppSettings.normalizedQuickStakesList(list)
            }
        }
    }

    private func restoreDefaultStakes() {
        settingsStore.update { settings in
            settings.quickStakesList = AppSettings.defaultQuickStakesList
        }
    }

    private func removeQuickStake(at offsets: IndexSet) {
        settingsStore.update { settings in
            var updated = settings.quickStakesList
            for index in offsets.sorted(by: >) {
                guard updated.indices.contains(index) else { continue }
                updated.remove(at: index)
            }
            settings.quickStakesList = AppSettings.normalizedQuickStakesList(updated)
        }
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateCurrency(to newCurrency: String) {
        let oldCurrency = settingsStore.settings.currency
        settingsStore.update { settings in
            if let currentDefaultStakes = normalizedText(settings.defaultStakes) {
                for item in settings.quickStakesList {
                    if let preset = StakesPreset(rawValue: item) {
                        let normalizedCurrent = AppSettings.normalizedCustomStakesValue(currentDefaultStakes) ?? currentDefaultStakes
                        let normalizedStored = AppSettings.normalizedCustomStakesValue(preset.storedValue(currency: oldCurrency))
                            ?? preset.storedValue(currency: oldCurrency)
                        if normalizedCurrent.caseInsensitiveCompare(normalizedStored) == .orderedSame {
                            settings.defaultStakes = preset.storedValue(currency: newCurrency)
                            break
                        }
                    }
                }
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

    private func removeQuickVenues(at offsets: IndexSet) {
        let options = venueQuickOptions
        for index in offsets.sorted(by: >) {
            guard options.indices.contains(index) else { continue }
            removeQuickVenue(options[index].venue)
        }
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
