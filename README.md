# Poker Bankroll AI

<p>
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/SwiftUI-iOS%2017+-blue.svg" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT">
</p>

**Poker Bankroll AI** is an iOS app I built for tracking poker sessions, bankroll, and performance. It’s live on the App Store as **Poker Bankroll AI**.

**[Download the app (free trial)](https://apps.apple.com/redeem?ctx=offercodes&id=6759470443&code=PALUMBO)**

---

## What I Built

A full-stack iOS app that lets players log sessions in plain English (“Won $200 at 1/2 NLH at Bellagio, 4 hours”), view bankroll and analytics, and sync data across devices. The AI session logger supports both direct API calls and a Cloudflare Worker proxy so API keys stay server-side.

### Technical Highlights

- **SwiftUI** – Declarative UI, `@ObservableObject` state, custom layouts
- **AI integration** – Gemini and OpenAI with fallback to a rule-based parser when offline
- **Cloudflare Worker** – TypeScript proxy for AI requests so keys never ship in the app
- **iCloud sync** – Key-value and document sync across devices
- **StoreKit 2** – In-app purchase for Premium (unlimited AI, full charts)
- **Custom equity engine** – Exact enumeration for small runouts, Monte Carlo for larger ones (NLH, PLO, PLO-5)
- **Natural language parsing** – Regex-based parser for stakes, dates, amounts, venues, and variants

### Architecture

- **Models** – `PokerSession` (Codable), `AppSettings` with migration for legacy fields
- **State** – `SessionStore` and `SettingsStore` with iCloud merge
- **Services** – `AISessionService` (routing, retries, rate limits), `SessionParserService` (offline parsing), `PokerEquityEngine` (hand evaluation)
- **Views** – Tab-based navigation, forms, charts, calendar, and AI chat UI

### Features

| Area | What it does |
|------|--------------|
| **AI Session Crafter** | Natural language → structured session (amount, stakes, venue, hours, variant) |
| **Bankroll & Stats** | Live bankroll, win rate, hourly rate, streaks, tournament ROI |
| **Charts** | Cumulative profit, monthly profit, breakdown by variant (Premium) |
| **Odds Calculator** | Hand equity for NLH/PLO/PLO-5, attach hands to sessions |
| **Organization** | Search, filters, calendar, swipe actions, CSV export |
| **Sync** | iCloud Key-Value for settings, session data across devices |

---

## Project Structure

```
PokerTrackerIOS/
├── Models/          # PokerSession, AppSettings
├── Views/           # Dashboard, Sessions, Calendar, Analytics, Odds Calculator
├── Services/        # AISessionService, SessionParserService, PokerEquityEngine
├── Utilities/       # APIKeysLoader, VenueCleaner, SessionImageStore, ReminderManager
└── cloudflare-worker/   # TypeScript Worker for AI proxy
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
