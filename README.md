# Poker Tracker iOS

A comprehensive SwiftUI iOS app for tracking poker wins, losses, and performance.

## Features

### Session Tracking
- **Log sessions** – Record wins/losses with amount, date, game type
- **Hours played** – Track session duration for hourly rate
- **Stakes & venue** – Record stakes (e.g. $1/$2) and location
- **Tournament details** – Buy-in, cash out, position, rebuys for tournaments
- **Hand notes** – Record notable hands for review
- **Game types** – Cash, Tournament, Sit & Go, Home Game, Online

### Bankroll Management
- **Starting bankroll** – Set your initial bankroll
- **Live bankroll** – Auto-calculated (starting + total P/L)
- **Low bankroll alert** – Get notified when bankroll drops below a threshold

### Analytics
- **Profit over time chart** – Visualize your running profit
- **Monthly profit chart** – See profit by month
- **Sessions by game type** – Bar chart breakdown
- **Key metrics** – Win rate, average session, best streak
- **Hourly rate** – Track $/hr when hours are logged
- **Tournament ROI** – Return on investment for tournaments

### Goals & Achievements
- **Custom goals** – Profit targets, session counts, win streaks
- **Achievements** – First Blood, Grinder, Hot Streak, High Roller, and more
- **Progress tracking** – See how close you are to each goal

### Organization
- **Search** – Find sessions by notes, venue, or stakes
- **Filters** – By game type and date range
- **Swipe actions** – Swipe to edit or delete (with confirmation)
- **Edit sessions** – Update any session after logging
- **Share session** – Share a session summary via Messages, Mail, etc.
- **Export to CSV** – Share your data for backup or analysis

### Quick Entry
- **Quick Add** – Log amount + win/loss in seconds (uses last session defaults)
- **Full Log** – Complete form with all details
- **Stakes chips** – One-tap stakes selection ($1/$2, $2/$5, etc.)
- **Amount toolbar** – +25, +50, +100 quick-add buttons above keyboard

### UX
- **Onboarding** – Welcome flow for first-time users
- **Haptic feedback** – Tactile response on key actions
- **Pull to refresh** – Refresh session lists
- **This month** – Dashboard stat for current month profit

## API Key Setup (keeps your key off GitHub)

Your API key stays local and is never pushed to GitHub.

**Option 1: APIKeys.plist (recommended for development)**  
1. Copy `PokerTrackerIOS/APIKeys.example.plist` to `APIKeys.plist` (same folder)  
2. Open `APIKeys.plist` and replace the placeholder values with your real keys  
3. `APIKeys.plist` is in `.gitignore`—it will not be committed when you push  

**Option 2: In-app Settings**  
Add your key in the app’s Settings screen. It’s stored on the device only.

- Never hardcode keys in Swift files  
- If a key is exposed, revoke it at aistudio.google.com or platform.openai.com

## Requirements

- Xcode 15+
- iOS 17.0+
- Swift 5.9+

## Getting Started

1. Open `PokerTrackerIOS.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a simulator or device (⌘R)

## Project Structure

```
PokerTrackerIOS/
├── PokerTrackerIOSApp.swift
├── ContentView.swift
├── SessionStore.swift
├── SettingsStore.swift
├── Models/
│   ├── PokerSession.swift
│   ├── AppSettings.swift
│   └── Goal.swift
├── Views/
│   ├── MainTabView.swift
│   ├── DashboardView.swift
│   ├── SessionsListView.swift
│   ├── SessionDetailView.swift
│   ├── EditSessionView.swift
│   ├── AddSessionView.swift
│   ├── QuickAddView.swift
│   ├── OnboardingView.swift
│   ├── AnalyticsView.swift
│   ├── GoalsView.swift
│   └── SettingsView.swift
├── Components/
│   ├── StatCard.swift
│   └── SessionRowView.swift
├── Utilities/
│   └── HapticManager.swift
└── Assets.xcassets
```

## Usage

1. **Dashboard** – View bankroll, stats, and recent sessions. Tap + for Quick Add or Full Log.
2. **Sessions** – Browse all sessions, search, filter. Swipe to edit/delete, tap for details.
3. **Analytics** – Charts and key metrics.
4. **Goals** – Set goals and unlock achievements.
5. **Settings** – Configure bankroll, currency, and export data.
