export interface Env {
  GEMINI_API_KEY: string;
  OPENAI_API_KEY?: string;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface HistoryMessage {
  role: "user" | "assistant";
  text: string;
}

interface RequestBody {
  userId: string;
  conversationId: string;
  message: string;
  history?: HistoryMessage[];
  sessionContext?: string;
  provider?: "gemini" | "openai";
}

interface NormalizedResponse {
  resultType: "followUp" | "complete" | "update";
  text: string;
  parsedSession?: Record<string, unknown>;
  update?: { sessionNumber: number; fields: Record<string, unknown> };
}

interface ErrorBody {
  error: { code: string; message: string };
}

// ---------------------------------------------------------------------------
// Lightweight per-IP rate limiter (best-effort, in-isolate memory)
// ---------------------------------------------------------------------------

const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 30;
const ipLog = new Map<string, number[]>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  let ts = ipLog.get(ip);
  if (!ts) {
    ts = [];
    ipLog.set(ip, ts);
  }
  // Evict old entries
  while (ts.length > 0 && now - ts[0] > RATE_WINDOW_MS) ts.shift();
  if (ts.length >= RATE_MAX) return true;
  ts.push(now);
  return false;
}

// Periodically prune stale IPs (every ~500 requests)
let requestCounter = 0;
function maybePruneIpLog() {
  if (++requestCounter % 500 !== 0) return;
  const cutoff = Date.now() - RATE_WINDOW_MS;
  for (const [ip, ts] of ipLog) {
    if (ts.length === 0 || ts[ts.length - 1] < cutoff) ipLog.delete(ip);
  }
}

// ---------------------------------------------------------------------------
// Size limits
// ---------------------------------------------------------------------------

const MAX_MESSAGE_LEN = 2000;
const MAX_CONTEXT_LEN = 4000;
const MAX_HISTORY = 5;

function clamp(s: string | undefined, max: number): string {
  if (!s) return "";
  return s.length > max ? s.slice(0, max) : s;
}

// ---------------------------------------------------------------------------
// System prompt (mirrors the iOS prompt exactly)
// ---------------------------------------------------------------------------

function buildSystemPrompt(sessionContext: string): string {
  const now = new Date();
  const iso = now.toISOString();
  const dayName = now.toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  const tagList = "A-Game, Tilt, Tough Table, Soft Table, Bad Beat, Run Good, Tired, Focused, Marathon, Confident, Deep Stack, Stressful, Profitable, Experimental, Big Bluff";

  let prompt = `You are a poker session logging assistant inside a tracking app. You help log new sessions and update existing ones.

REFERENCE DATE (critical):
Today is ${dayName}. The current date in ISO 8601 is: ${iso}. Use this as the ONLY reference when interpreting relative dates.
- Relative phrases like "last Saturday", "yesterday", "played last weekend", "this past Friday" MUST be computed relative to TODAY above.
- The session date must always be in the recent past (within the last few weeks at most). Never output a date from years ago for relative phrases.

CAPABILITIES:
1. LOG NEW SESSION - gather info and return JSON to create a session
2. UPDATE EXISTING SESSION - modify a session by its # number
3. ASK FOR DETAILS - if user gives very minimal info, ask follow-up questions

CRITICAL — AMOUNT EXTRACTION (READ CAREFULLY):
- "amount" is ALWAYS the user's FINAL NET profit or loss — the money they actually took home.
- LOOK FOR KEYWORDS: "made", "won", "up", "lost", "down" followed by a dollar figure. That figure is the amount.
- IGNORE peak/high-water-mark numbers. Words like "was up", "originally up", "peaked at" describe mid-session swings, NOT the final result.
- EXAMPLE: "made 600 bucks ... was originally up 1200 but punted" → amount is 600 (NOT 1200). The 1200 is a mid-session peak. The "made 600" is what they took home. Put "Was originally up 1200 but punted" into notes.
- EXAMPLE: "won 300 but was up 800 at one point" → amount is 300 (NOT 800).
- EXAMPLE: "lost 500, was stuck 1000 earlier but fought back" → amount is -500.
- If user says "bought in for X, cashed out for Y", compute amount as Y - X.
- Positive amount = win, negative = loss.
- WHEN IN DOUBT: use the number attached to "made/won/lost/down/up" at the START of the message, not numbers mentioned as past peaks.

NOTES & HAND NOTES:
- Any extra context the user provides beyond the core session data (amount, stakes, hours, venue, variant) should go into "notes".
- Examples: "was on tilt", "table was really soft", "ran bad but played well", "was up 1200 but punted half back" — put these in "notes" as-is.
- Do NOT ignore this context. Capture it faithfully.

TAGS (strict rules):
- Available tags: ${tagList}
- ONLY add a tag when the user EXPLICITLY mentions the concept using clear, unambiguous language. Never infer or guess tags.
- Do NOT add tags based on the session result alone. Winning does NOT mean "Profitable" or "Run Good". Losing does NOT mean "Bad Beat" or "Tilt".
- Each tag requires the user to specifically describe that experience:
  • "Tilt" — user says "tilt", "tilted", "on tilt", "steaming", "lost my cool"
  • "Tired" — user says "tired", "exhausted", "sleepy", "fatigued"
  • "Focused" — user says "focused", "in the zone", "locked in", "dialed in"
  • "A-Game" — user says "A-game", "played great", "played my best", "peak performance"
  • "Bad Beat" — user says "bad beat", "got sucked out", "cooler", "got rivered"
  • "Run Good" — user says "run good", "running hot", "heater", "couldn't lose"
  • "Soft Table" — user says "soft table", "soft game", "fishy", "fish", "easy game"
  • "Tough Table" — user says "tough table", "tough lineup", "all regs", "tough game"
  • "Marathon" — user says "marathon", "long session", "grind" AND hours >= 6
  • "Deep Stack" — user says "deep stack", "deep stacked"
  • "Big Bluff" — user says "big bluff", "bluffed", "hero call"
  • "Confident" — user says "confident", "felt confident"
  • "Stressful" — user says "stressful", "stressed", "sweating", "nervous"
  • "Profitable" — user says "crushing", "printing money", "crushing it"
  • "Experimental" — user says "experimental", "trying new", "new strategy", "testing"
- When in doubt, do NOT add the tag. Return an empty array [] if no tags are explicitly mentioned.

RULES FOR NEW SESSIONS:
- If the user gives ONLY an amount (e.g. "won 50" or "lost 200") with no other details, ask a SHORT friendly question to get more info. Ask about 2-3 things at once (like stakes, game type, hours, venue).
- If the user provides an amount PLUS at least one other detail (stakes, venue, hours, game type, etc.), go ahead and log it.
- When you have enough info, respond with ONLY a JSON object:
  {"action": "create", "amount": number, "hoursPlayed": number|null, "stakes": string|null, "venue": string|null, "gameFormat": string|null, "variant": string|null, "notes": string|null, "buyIn": number|null, "cashOut": number|null, "date": string|null, "tournamentPosition": number|null, "rebuys": number|null, "handNotes": string|null, "tags": [string]}
- "date" must be ISO 8601 (YYYY-MM-DD or full ISO). If the user says "yesterday", "last Saturday", "played last weekend", etc., compute that date relative to TODAY and output it. Never use a date from a previous year for relative phrases.
- Default variant to "No Limit Hold'em" and format to "Cash Game" if not mentioned.

RULES FOR UPDATES:
- If the user says something like "update session 3" or "change session #5 stakes to 2/5", respond with:
  {"action": "update", "sessionNumber": number, "fields": {"fieldName": newValue, ...}}
- Valid field names: amount, hoursPlayed, stakes, venue, gameFormat, variant, notes, buyIn, cashOut, date, tournamentPosition, rebuys, handNotes, tags
- If the user wants to update but doesn't specify which session, ask them which session number.

GENERAL RULES:
- Keep responses SHORT and friendly. 1-2 sentences max for follow-ups.
- Never wrap JSON in markdown code blocks. Return raw JSON only when creating/updating.
- If you're asking a question (not creating/updating), respond with plain text only.`;

  if (sessionContext) {
    prompt += `\n\nEXISTING SESSIONS (for reference when updating):\n${sessionContext}`;
  }
  return prompt;
}

// ---------------------------------------------------------------------------
// Provider calls
// ---------------------------------------------------------------------------

const GEMINI_MODEL_BASIC = "gemini-2.5-flash-lite";
const GEMINI_MODEL_ADVANCED = "gemini-2.5-pro";
const MESSAGE_LENGTH_THRESHOLD = 250;

function pickGeminiModel(messageLength: number): string {
  return messageLength > MESSAGE_LENGTH_THRESHOLD ? GEMINI_MODEL_ADVANCED : GEMINI_MODEL_BASIC;
}

async function callGemini(
  messages: HistoryMessage[],
  systemPrompt: string,
  apiKey: string,
  model?: string,
): Promise<string> {
  const contents = messages.map((m) => ({
    role: m.role === "user" ? "user" : "model",
    parts: [{ text: m.text }],
  }));

  const userMsg = messages.find((m) => m.role === "user")?.text ?? "";
  const chosenModel = model ?? pickGeminiModel(userMsg.length);

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${chosenModel}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: { temperature: 0.2, maxOutputTokens: 500 },
      }),
    },
  );

  if (!res.ok) {
    const body = await res.text();
    throw new ProviderError(res.status, `Gemini ${res.status}: ${body}`);
  }

  const json = (await res.json()) as Record<string, unknown>;
  const candidates = json.candidates as Array<Record<string, unknown>> | undefined;
  const parts = ((candidates?.[0]?.content as Record<string, unknown>)?.parts as Array<Record<string, unknown>>) ?? [];
  const responsePart = parts.filter((p) => !p.thought).pop();
  const text = responsePart?.text as string | undefined;
  if (!text) throw new ProviderError(500, "Empty Gemini response");
  return text;
}

async function callOpenAI(
  messages: HistoryMessage[],
  systemPrompt: string,
  apiKey: string,
): Promise<string> {
  const oaiMessages = [
    { role: "system", content: systemPrompt },
    ...messages.map((m) => ({
      role: m.role === "user" ? "user" : ("assistant" as const),
      content: m.text,
    })),
  ];

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: oaiMessages,
      temperature: 0.2,
      max_tokens: 500,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new ProviderError(res.status, `OpenAI ${res.status}: ${body}`);
  }

  const json = (await res.json()) as Record<string, unknown>;
  const choices = json.choices as Array<Record<string, unknown>> | undefined;
  const content = ((choices?.[0]?.message as Record<string, unknown>)?.content as string) ?? "";
  if (!content) throw new ProviderError(500, "Empty OpenAI response");
  return content;
}

class ProviderError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
  get retryable(): boolean {
    return this.status === 429 || this.status >= 500;
  }
}

// ---------------------------------------------------------------------------
// Retry wrapper
// ---------------------------------------------------------------------------

async function withRetry(fn: () => Promise<string>, maxRetries = 2): Promise<string> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (err instanceof ProviderError && err.retryable && attempt < maxRetries) {
        await new Promise((r) => setTimeout(r, 500 * 2 ** attempt));
        continue;
      }
      throw err;
    }
  }
  throw lastErr;
}

// ---------------------------------------------------------------------------
// Response classification (mirrors iOS classifyResponse)
// ---------------------------------------------------------------------------

function classifyResponse(rawText: string): NormalizedResponse {
  const cleaned = rawText
    .replace(/```json/g, "")
    .replace(/```/g, "")
    .trim();

  if (!cleaned.startsWith("{")) {
    return { resultType: "followUp", text: cleaned };
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    return { resultType: "followUp", text: cleaned };
  }

  const action = (parsed.action as string) ?? "create";

  if (action === "update") {
    const sessionNumber = toNumber(parsed.sessionNumber);
    const fields = parsed.fields as Record<string, unknown> | undefined;
    if (sessionNumber != null && fields) {
      return {
        resultType: "update",
        text: cleaned,
        update: { sessionNumber, fields },
      };
    }
    return { resultType: "followUp", text: cleaned };
  }

  // create action
  const amount = toNumber(parsed.amount);
  if (amount == null) {
    return { resultType: "followUp", text: cleaned };
  }

  const session: Record<string, unknown> = {
    amount,
    hoursPlayed: toNumber(parsed.hoursPlayed) ?? null,
    stakes: parsed.stakes ?? null,
    venue: parsed.venue ?? null,
    gameFormat: parsed.gameFormat ?? parsed.gameType ?? "Cash Game",
    variant: parsed.variant ?? null,
    notes: parsed.notes ?? null,
    buyIn: toNumber(parsed.buyIn) ?? null,
    cashOut: toNumber(parsed.cashOut) ?? null,
    date: parsed.date ?? null,
    tournamentPosition: toNumber(parsed.tournamentPosition) ?? null,
    rebuys: toNumber(parsed.rebuys) ?? null,
    handNotes: parsed.handNotes ?? null,
    tags: Array.isArray(parsed.tags) ? parsed.tags : [],
  };

  if (!isLoggable(session)) {
    return {
      resultType: "followUp",
      text:
        "I need one or two more details before I can log this. What stakes, venue, hours played, or session date should I use?",
    };
  }

  return { resultType: "complete", text: cleaned, parsedSession: session };
}

function toNumber(v: unknown): number | null {
  if (typeof v === "number" && isFinite(v)) return v;
  if (typeof v === "string") {
    const n = parseFloat(v.replace(/[$,]/g, ""));
    return isFinite(n) ? n : null;
  }
  return null;
}

function isLoggable(s: Record<string, unknown>): boolean {
  const hasDetail =
    s.hoursPlayed != null ||
    hasText(s.stakes) ||
    hasText(s.venue) ||
    hasText(s.notes) ||
    hasText(s.variant) ||
    s.buyIn != null ||
    s.cashOut != null ||
    s.date != null ||
    s.tournamentPosition != null ||
    s.rebuys != null ||
    hasText(s.handNotes);
  return hasDetail;
}

function hasText(v: unknown): boolean {
  return typeof v === "string" && v.trim().length > 0;
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

function jsonOk(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonErr(code: string, message: string, status: number): Response {
  const body: ErrorBody = { error: { code, message } };
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    maybePruneIpLog();

    const url = new URL(request.url);

    // Health
    if (request.method === "GET" && url.pathname === "/v1/health") {
      return jsonOk({ ok: true });
    }

    // Session crafter
    if (request.method === "POST" && url.pathname === "/v1/ai/session-crafter") {
      return handleSessionCrafter(request, env);
    }

    return jsonErr("not_found", "Not found", 404);
  },
} satisfies ExportedHandler<Env>;

async function handleSessionCrafter(request: Request, env: Env): Promise<Response> {
  // Rate limit
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  if (rateLimited(ip)) {
    return jsonErr("rate_limited", "Too many requests. Please wait a moment.", 429);
  }

  // Parse body
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return jsonErr("bad_request", "Invalid JSON body", 400);
  }

  // Validate required fields
  if (!body.userId || typeof body.userId !== "string") {
    return jsonErr("bad_request", "userId is required", 400);
  }
  if (!body.conversationId || typeof body.conversationId !== "string") {
    return jsonErr("bad_request", "conversationId is required", 400);
  }
  if (!body.message || typeof body.message !== "string") {
    return jsonErr("bad_request", "message is required", 400);
  }

  // Sanitize & limit
  const message = clamp(body.message.trim(), MAX_MESSAGE_LEN);
  const sessionContext = clamp(body.sessionContext?.trim(), MAX_CONTEXT_LEN);
  const history: HistoryMessage[] = (body.history ?? [])
    .slice(-MAX_HISTORY)
    .filter(
      (h): h is HistoryMessage =>
        (h.role === "user" || h.role === "assistant") && typeof h.text === "string",
    )
    .map((h) => ({ role: h.role, text: clamp(h.text, MAX_MESSAGE_LEN) }));

  // Build full message list: history + current user message
  const fullMessages: HistoryMessage[] = [...history, { role: "user", text: message }];
  const systemPrompt = buildSystemPrompt(sessionContext);

  // Pick provider
  const preferredProvider = body.provider ?? "gemini";
  const hasGemini = !!env.GEMINI_API_KEY;
  const hasOpenAI = !!env.OPENAI_API_KEY;

  if (!hasGemini && !hasOpenAI) {
    return jsonErr("provider_error", "No AI provider configured on server", 502);
  }

  try {
    let rawText: string;

    if (preferredProvider === "openai" && hasOpenAI) {
      rawText = await withRetry(() => callOpenAI(fullMessages, systemPrompt, env.OPENAI_API_KEY!));
    } else if (hasGemini) {
      try {
        rawText = await withRetry(() => callGemini(fullMessages, systemPrompt, env.GEMINI_API_KEY));
      } catch (err) {
        if (err instanceof ProviderError && err.status === 429) {
          try {
            rawText = await callGemini(fullMessages, systemPrompt, env.GEMINI_API_KEY, GEMINI_MODEL_BASIC);
          } catch (fallbackErr) {
            if (hasOpenAI) {
              rawText = await withRetry(() =>
                callOpenAI(fullMessages, systemPrompt, env.OPENAI_API_KEY!),
              );
            } else {
              throw fallbackErr;
            }
          }
        } else if (hasOpenAI) {
          rawText = await withRetry(() =>
            callOpenAI(fullMessages, systemPrompt, env.OPENAI_API_KEY!),
          );
        } else {
          throw err;
        }
      }
    } else {
      rawText = await withRetry(() => callOpenAI(fullMessages, systemPrompt, env.OPENAI_API_KEY!));
    }

    const result = classifyResponse(rawText);
    return jsonOk(result);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    const status = err instanceof ProviderError ? (err.status === 429 ? 429 : 502) : 500;
    const code = status === 429 ? "rate_limited" : "provider_error";
    return jsonErr(code, msg, status);
  }
}
