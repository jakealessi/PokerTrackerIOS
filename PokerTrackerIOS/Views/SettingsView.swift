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

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty && version != build:
            return "\(version) (\(build))"
        case let (version?, _ ) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "Unknown"
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                premiumSection
                gameDefaultsSection
                bankrollSection
                currencySection
                displayPreferencesSection
                preferencesSection
                remindersSection
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

    private var premiumSection: some View {
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
                Button {
                    showingPaywall = true
                } label: {
                    Label("Subscribe to Premium", systemImage: "crown.fill")
                        .foregroundStyle(AppTheme.accent)
                }
            }
        } header: {
            Text("Premium")
        } footer: {
            if !subscriptionStore.isSubscribed {
                Text("Subscribe to unlock unlimited AI Session Crafter, Odds Calculator, and all stats charts.")
            }
        }
    }
    
    private var aiSection: some View {
        Section {
            SecureField("Gemini API Key", text: optionalStringBinding(\.geminiAPIKey))
            .textContentType(.password)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            
            SecureField("OpenAI API Key", text: optionalStringBinding(\.openAIAPIKey))
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
            Picker("Default Format", selection: settingBinding(\.defaultGameType)) {
                ForEach(GameType.formatOptions, id: \.self) { Text($0.rawValue).tag($0) }
            }
            
            Picker("Default Variant", selection: defaultVariantBinding) {
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
                TextField("0", value: startingBankrollBinding, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Bankroll")
        }
    }
    
    private var currencySection: some View {
        Section {
            Picker("Currency", selection: settingBinding(\.currency)) {
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
            Picker("Win / Loss Colors", selection: settingBinding(\.profitLossColorScheme)) {
                ForEach(ProfitLossColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
            .accessibilityHint("Choose colorblind-friendly alternatives")
            
            Toggle("Show Hourly Rate", isOn: settingBinding(\.showHourlyRate))
            
            Toggle("Haptic Feedback", isOn: settingBinding(\.hapticFeedback))
        } header: {
            Text("Preferences")
        } footer: {
            Text("Win/loss colors can be changed for colorblind accessibility.")
        }
    }

    private var displayPreferencesSection: some View {
        Section {
            Toggle("24-Hour Time", isOn: settingBinding(\.use24HourTime))

            Toggle("Compact Currency", isOn: settingBinding(\.useCompactCurrency))

            Toggle("Show Session Numbers", isOn: settingBinding(\.showSessionNumbers))
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

            Toggle("Confirm Before Delete", isOn: settingBinding(\.confirmBeforeDelete))
        } header: {
            Text("Data & Recovery")
        } footer: {
            Text("Backup/restore only affects session data. Restoring replaces all current sessions.")
        }
    }
    
    private var remindersSection: some View {
        Section {
            Toggle("Session Reminders", isOn: settingBinding(\.reminderEnabled))
        } header: {
            Text("Reminders")
        } footer: {
            Text("Reminders to log your sessions.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionText)
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
