//
//  SettingsView.swift
//  PokerTrackerIOS
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var showingExportSheet = false
    @State private var friendCodeInput = ""
    @State private var showingRedeemResult = false
    @State private var redeemSuccess = false
    @State private var exportData: String = ""
    @State private var showingRestoreImporter = false
    @State private var showingRestoreConfirm = false
    @State private var pendingRestoreData: Data?
    @State private var showingBackupExporter = false
    @State private var backupDocument = TextFileDocument(text: "")
    @State private var showingRestoreResult = false
    @State private var restoreResultTitle = "Restore"
    @State private var restoreResultMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                premiumCodeSection
                gameDefaultsSection
                bankrollSection
                currencySection
                displayPreferencesSection
                preferencesSection
                dataRecoverySection
                aboutSection
                aiSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                }
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
            .alert(redeemSuccess ? "Premium activated" : "Invalid code", isPresented: $showingRedeemResult) {
                Button("OK", role: .cancel) {
                    if redeemSuccess { friendCodeInput = "" }
                }
            } message: {
                Text(redeemSuccess ? "You have premium access. Thanks for being a friend!" : "That code isn’t valid. Check with the person who gave it to you.")
            }
        }
    }

    private var premiumCodeSection: some View {
        Section {
            if subscriptionStore.isSubscribed {
                HStack {
                    Label("Premium", systemImage: "crown.fill")
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Text("Active")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                HStack {
                    TextField("Friend or promo code", text: $friendCodeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Redeem") {
                        let code = friendCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !code.isEmpty else { return }
                        redeemSuccess = subscriptionStore.redeemFriendCode(code)
                        showingRedeemResult = true
                        if settingsStore.settings.hapticFeedback {
                            if redeemSuccess { HapticManager.success() } else { HapticManager.notification(.error) }
                        }
                    }
                    .disabled(friendCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        } header: {
            Text("Premium")
        } footer: {
            if !subscriptionStore.isSubscribed {
                Text("Have a code from a friend? Enter it here to unlock premium features.")
            }
        }
    }
    
    private var aiSection: some View {
        Section {
            SecureField("Gemini API Key", text: Binding(
                get: { settingsStore.settings.geminiAPIKey ?? "" },
                set: { val in
                    var s = settingsStore.settings
                    s.geminiAPIKey = val.isEmpty ? nil : val
                    settingsStore.settings = s
                }
            ))
            .textContentType(.password)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            
            SecureField("OpenAI API Key", text: Binding(
                get: { settingsStore.settings.openAIAPIKey ?? "" },
                set: { val in
                    var s = settingsStore.settings
                    s.openAIAPIKey = val.isEmpty ? nil : val
                    settingsStore.settings = s
                }
            ))
            .textContentType(.password)
            .autocapitalization(.none)
            .autocorrectionDisabled()
        } header: {
            Text("AI Session Logging")
        } footer: {
            Text("Use your own key for a more powerful model. Add a Gemini key (free at aistudio.google.com) or OpenAI key. Keys stored locally.")
        }
    }
    
    private var gameDefaultsSection: some View {
        Section {
            Picker("Default Format", selection: Binding(
                get: { settingsStore.settings.defaultGameType },
                set: { val in
                    var s = settingsStore.settings
                    s.defaultGameType = val
                    settingsStore.settings = s
                }
            )) {
                ForEach(GameType.formatOptions, id: \.self) { Text($0.rawValue).tag($0) }
            }
            
            Picker("Default Variant", selection: Binding(
                get: { settingsStore.settings.defaultVariant ?? PokerVariant.noLimitHoldem.rawValue },
                set: { val in
                    var s = settingsStore.settings
                    s.defaultVariant = val
                    settingsStore.settings = s
                }
            )) {
                ForEach(PokerVariant.allCases, id: \.rawValue) { variant in
                    Text(variant.rawValue).tag(variant.rawValue)
                }
            }
        } header: {
            Text("Game Defaults")
        }
    }
    
    private var bankrollSection: some View {
        Section {
            HStack {
                Text("Starting Bankroll")
                TextField("0", value: Binding(
                    get: { settingsStore.settings.startingBankroll },
                    set: { val in
                        var s = settingsStore.settings
                        s.startingBankroll = val
                        settingsStore.settings = s
                    }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Bankroll")
        }
    }
    
    private var currencySection: some View {
        Section {
            Picker("Currency", selection: Binding(
                get: { settingsStore.settings.currency },
                set: { val in
                    var s = settingsStore.settings
                    s.currency = val
                    settingsStore.settings = s
                }
            )) {
                Text("USD").tag("USD")
                Text("EUR").tag("EUR")
                Text("GBP").tag("GBP")
            }
        } header: {
            Text("Currency")
        }
    }
    
    private var preferencesSection: some View {
        Section {
            Picker("Win / Loss Colors", selection: Binding(
                get: { settingsStore.settings.profitLossColorScheme },
                set: { val in
                    var s = settingsStore.settings
                    s.profitLossColorScheme = val
                    settingsStore.settings = s
                }
            )) {
                ForEach(ProfitLossColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
            .accessibilityHint("Choose colorblind-friendly alternatives")
            
            Toggle("Show Hourly Rate", isOn: Binding(
                get: { settingsStore.settings.showHourlyRate },
                set: { val in
                    var s = settingsStore.settings
                    s.showHourlyRate = val
                    settingsStore.settings = s
                }
            ))
            
            Toggle("Haptic Feedback", isOn: Binding(
                get: { settingsStore.settings.hapticFeedback },
                set: { val in
                    var s = settingsStore.settings
                    s.hapticFeedback = val
                    settingsStore.settings = s
                }
            ))
        } header: {
            Text("Preferences")
        } footer: {
            Text("Win/loss colors can be changed for colorblind accessibility.")
        }
    }

    private var displayPreferencesSection: some View {
        Section {
            Toggle("24-Hour Time", isOn: Binding(
                get: { settingsStore.settings.use24HourTime },
                set: { val in
                    var s = settingsStore.settings
                    s.use24HourTime = val
                    settingsStore.settings = s
                }
            ))

            Toggle("Compact Currency", isOn: Binding(
                get: { settingsStore.settings.useCompactCurrency },
                set: { val in
                    var s = settingsStore.settings
                    s.useCompactCurrency = val
                    settingsStore.settings = s
                }
            ))

            Toggle("Show Session Numbers", isOn: Binding(
                get: { settingsStore.settings.showSessionNumbers },
                set: { val in
                    var s = settingsStore.settings
                    s.showSessionNumbers = val
                    settingsStore.settings = s
                }
            ))
        } header: {
            Text("Display Preferences")
        } footer: {
            Text("Controls how session values and time are shown across the app.")
        }
    }

    private var dataRecoverySection: some View {
        Section {
            Button {
                exportData = sessionStore.exportCSV(currency: settingsStore.settings.currency)
                showingExportSheet = true
            } label: {
                Label("Export to CSV", systemImage: "square.and.arrow.up")
                    .foregroundStyle(AppTheme.accent)
            }

            Button {
                if let backup = sessionStore.exportBackupJSON() {
                    backupDocument = TextFileDocument(text: backup)
                    showingBackupExporter = true
                } else {
                    restoreResultTitle = "Backup Failed"
                    restoreResultMessage = "Could not generate backup data."
                    showingRestoreResult = true
                }
            } label: {
                Label("Backup Sessions (JSON)", systemImage: "externaldrive.badge.plus")
                    .foregroundStyle(AppTheme.accent)
            }

            Button {
                showingRestoreImporter = true
            } label: {
                Label("Restore Sessions (JSON)", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
            }

            Toggle("Confirm Before Delete", isOn: Binding(
                get: { settingsStore.settings.confirmBeforeDelete },
                set: { val in
                    var s = settingsStore.settings
                    s.confirmBeforeDelete = val
                    settingsStore.settings = s
                }
            ))
        } header: {
            Text("Data & Recovery")
        } footer: {
            Text("Backup/restore only affects session data. Restoring replaces all current sessions.")
        }
    }
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            
            Link(destination: AppURLs.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(AppTheme.accent)
            }
            
            Link(destination: AppURLs.support) {
                Label("Support", systemImage: "questionmark.circle")
                    .foregroundStyle(AppTheme.accent)
            }
        } header: {
            Text("About")
        }
    }

    private func handleRestoreImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            restoreResultTitle = "Restore Failed"
            restoreResultMessage = error.localizedDescription
            showingRestoreResult = true
        case .success(let urls):
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
                restoreResultTitle = "Restore Failed"
                restoreResultMessage = error.localizedDescription
                showingRestoreResult = true
            }
        }
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

#Preview {
    SettingsView()
        .environmentObject(SessionStore())
        .environmentObject(SettingsStore())
        .environmentObject(SubscriptionStore.shared)
}
