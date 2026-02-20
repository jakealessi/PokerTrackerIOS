# Poker Bankroll AI

A SwiftUI iOS app for tracking poker wins, losses, and performance. Log sessions with AI assistance, view stats and charts, and sync data across devices via iCloud.

## Features

### Session Tracking
- **Log sessions** – Record wins/losses with amount, date, game type
- **Hours played** – Track session duration for hourly rate
- **Stakes & venue** – Record stakes (e.g. $1/$2) and location, with one-tap presets
- **Tournament details** – Buy-in, cash out, position, rebuys for tournaments
- **Hand notes** – Record notable hands for review
- **Photos** – Attach images to sessions
- **Game types** – Cash, Tournament, Sit & Go, Home Game, Online

### AI Session Logging
- **Natural language input** – Type "Won $200 at 1/2 NLH" or "Update session #3 stakes to 2/5"
- **20 free uses** – Try AI session crafting before Premium
- **Gemini or OpenAI** – Use your own API key for more powerful models

### Bankroll & Analytics
- **Starting bankroll** – Set your initial bankroll
- **Live bankroll** – Auto-calculated (starting + total P/L)
- **Profit over time chart** – Cumulative profit (Premium)
- **Monthly profit chart** – Profit by month (Premium)
- **Win/loss breakdown** – Donut chart (Premium)
- **By variant** – Sessions and profit by game variant (Premium)
- **Key metrics** – Win rate, average session, best streak, hourly rate, tournament ROI

### Organization
- **Search** – Find sessions by notes, venue, stakes, or variant
- **Filters** – By game type and date range
- **Calendar** – View sessions by day with daily profit
- **Swipe actions** – Swipe to edit or delete (with confirmation)
- **Edit sessions** – Update any session after logging
- **Share session** – Share a session summary via Messages, Mail, etc.
- **Export to CSV** – Share your data for backup or analysis

### Premium Subscription
- **Unlimited AI uses** – No cap on AI session crafting
- **All charts** – Full access to stats and analytics
- **$4.99/month** – 1 month free trial

### UX
- **Onboarding** – Welcome flow for first-time users
- **Haptic feedback** – Tactile response on key actions
- **iCloud sync** – Data syncs across devices when signed in with the same Apple ID
- **This month** – Dashboard stat for current month profit

## API Key Setup (keeps your key off GitHub)

Your API key stays local and is never pushed to GitHub.

**Option 1: APIKeys.plist (recommended for development)**  
1. Copy `PokerTrackerIOS/APIKeys.example.plist` to `APIKeys.plist` (same folder)  
2. Open `APIKeys.plist` and replace the placeholder values with your real keys  
3. `APIKeys.plist` is in `.gitignore`—it will not be committed when you push  

**Option 2: In-app Settings**  
Add your key in the app's Settings screen. It's stored on the device only.

- Never hardcode keys in Swift files  
- If a key is exposed, revoke it at aistudio.google.com or platform.openai.com

## Requirements

- Xcode 15+
- iOS 17.0+
- Swift 5.9+

## Getting Started

1. Open `PokerTrackerIOS.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Enable iCloud capability (Key-Value and Documents)
4. Build and run on a simulator or device (⌘R)

## Project Structure

```
PokerTrackerIOS/
├── PokerTrackerIOSApp.swift
├── ContentView.swift
├── SessionStore.swift
├── SettingsStore.swift
├── SubscriptionStore.swift
├── Models/
│   ├── PokerSession.swift
│   └── AppSettings.swift
├── Views/
│   ├── MainTabView.swift
│   ├── DashboardView.swift
│   ├── SessionsListView.swift
│   ├── SessionDetailView.swift
│   ├── EditSessionView.swift
│   ├── AddSessionView.swift
│   ├── OnboardingView.swift
│   ├── AnalyticsView.swift
│   ├── CalendarView.swift
│   ├── SubscriptionPaywallView.swift
│   └── SettingsView.swift
├── Components/
│   ├── SessionRowView.swift
│   └── ImageAttachmentsSection.swift
├── Services/
│   ├── AISessionService.swift
│   └── SessionParserService.swift
├── Utilities/
│   ├── AppTheme.swift
│   ├── HapticManager.swift
│   ├── APIKeysLoader.swift
│   ├── AppURLs.swift
│   ├── AISessionCrafterUsage.swift
│   ├── ActivitySheet.swift
│   ├── SessionImageStore.swift
│   ├── VenueCleaner.swift
│   └── iCloudStore.swift
├── website/
│   ├── privacy-policy.html
│   └── support.html
└── Assets.xcassets
```

## Usage

1. **Home** – View bankroll, stats, and log sessions via AI chat or tap + for the full form
2. **Stats** – Summary cards, charts (Premium), and key metrics
3. **Calendar** – Browse sessions by month and day
4. **Sessions** – Search, filter, swipe to edit/delete, tap for details
5. **Settings** – Bankroll, currency, game defaults, AI keys, export, privacy policy, support
