# Poker Tracker AI Proxy

Cloudflare Worker that proxies AI requests for the Poker Tracker iOS app. Keeps provider API keys server-side and normalizes responses.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/health` | Health check → `{ "ok": true }` |
| `POST` | `/v1/ai/session-crafter` | Conversational session logging |

## Setup

```bash
npm install
wrangler login   # Creates .wrangler/ (gitignored)

# Required
wrangler secret put GEMINI_API_KEY

# Optional (fallback)
wrangler secret put OPENAI_API_KEY
```

## Deploy

```bash
wrangler deploy
```

After deploy, note your Worker URL (e.g. `https://poker-tracker-ai-proxy.<subdomain>.workers.dev`) and set it as the Worker Base URL in the iOS app.

## Local dev

```bash
# Create .dev.vars with your keys:
# GEMINI_API_KEY=your-key
# OPENAI_API_KEY=your-key

npm run dev
```

## Request format

```json
{
  "userId": "anonymous-uuid",
  "conversationId": "conversation-uuid",
  "message": "Won $200 at 1/2 NLH at Bellagio, 4 hours",
  "history": [
    { "role": "user", "text": "previous message" },
    { "role": "assistant", "text": "previous response" }
  ],
  "sessionContext": "#1: +$150 on 3/1/26, $1/$2...",
  "provider": "gemini"
}
```

## Response format

```json
{
  "resultType": "followUp|complete|update",
  "text": "...",
  "parsedSession": { "amount": 200, "stakes": "1/2", "..." : "..." },
  "update": { "sessionNumber": 3, "fields": { "stakes": "2/5" } }
}
```
