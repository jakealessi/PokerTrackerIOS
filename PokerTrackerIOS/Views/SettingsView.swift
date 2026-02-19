//
//  SettingsView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingExportSheet = false
    @State private var exportData: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                gameDefaultsSection
                bankrollSection
                currencySection
                preferencesSection
                exportSection
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
    
    private var exportSection: some View {
        Section {
            Button {
                exportData = sessionStore.exportCSV(currency: settingsStore.settings.currency)
                showingExportSheet = true
            } label: {
                Label("Export to CSV", systemImage: "square.and.arrow.up")
                    .foregroundStyle(AppTheme.accent)
            }
        } header: {
            Text("Data")
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
}
