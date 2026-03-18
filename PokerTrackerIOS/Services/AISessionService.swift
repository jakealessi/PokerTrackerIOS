//
//  AISessionService.swift
//  PokerTrackerIOS
//
//  Conversational AI session logging.
//  Routes through user's own API key when available (direct call),
//  otherwise proxies via Cloudflare Worker (developer default key).
//  Falls back to offline regex parser if both paths fail.
//

import Foundation

// MARK: - Models

struct ParsedSession {
    let amount: Double
    let hoursPlayed: Double?
    let stakes: String?
    let venue: String?
    let rake: Double?
    let tips: Double?
    let food: Double?
    let travel: Double?
    let fees: Double?
    let gameType: GameType
    let variant: String?
    let notes: String?
    let buyIn: Double?
    let cashOut: Double?
    let date: Date?
    let tournamentPosition: Int?
    let rebuys: Int?
    let handNotes: String?
    let tags: [String]

    func withHoursPlayed(_ value: Double?) -> ParsedSession {
        ParsedSession(
            amount: amount,
            hoursPlayed: value,
            stakes: stakes,
            venue: venue,
            rake: rake,
            tips: tips,
            food: food,
            travel: travel,
            fees: fees,
            gameType: gameType,
            variant: variant,
            notes: notes,
            buyIn: buyIn,
            cashOut: cashOut,
            date: date,
            tournamentPosition: tournamentPosition,
            rebuys: rebuys,
            handNotes: handNotes,
            tags: tags
        )
    }

    func withDate(_ value: Date?) -> ParsedSession {
        ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
            rake: rake,
            tips: tips,
            food: food,
            travel: travel,
            fees: fees,
            gameType: gameType,
            variant: variant,
            notes: notes,
            buyIn: buyIn,
            cashOut: cashOut,
            date: value,
            tournamentPosition: tournamentPosition,
            rebuys: rebuys,
            handNotes: handNotes,
            tags: tags
        )
    }

    func mergingMissingFields(from signals: SessionParserService.ExtractedSessionSignals) -> ParsedSession {
        let inferredGameType: GameType = {
            guard let parsedType = signals.gameType else { return gameType }
            if parsedType == .plo {
                return .cash
            }
            if gameType == .cash && parsedType != .cash {
                return parsedType
            }
            return gameType
        }()

        let inferredVariant: String? = {
            if let variant {
                return variant
            }
            if signals.gameType == .plo {
                return signals.variant ?? PokerVariant.plo.rawValue
            }
            return signals.variant
        }()

        return ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed ?? signals.hoursPlayed,
            stakes: stakes ?? signals.stakes,
            venue: venue ?? signals.venue,
            rake: rake ?? signals.rake,
            tips: tips ?? signals.tips,
            food: food ?? signals.food,
            travel: travel ?? signals.travel,
            fees: fees ?? signals.fees,
            gameType: inferredGameType,
            variant: inferredVariant,
            notes: notes,
            buyIn: buyIn ?? signals.buyIn,
            cashOut: cashOut ?? signals.cashOut,
            date: date ?? signals.date,
            tournamentPosition: tournamentPosition ?? signals.tournamentPosition,
            rebuys: rebuys ?? signals.rebuys,
            handNotes: handNotes,
            tags: tags
        )
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String
    var card: Card? = nil
    
    enum Role: Equatable {
        case user
        case assistant
    }

    enum Card: Equatable {
        case session(SessionCard)
    }

    struct SessionCard: Equatable {
        let sessionID: UUID
        let headline: String
        let detail: String?
        let systemImage: String
    }
}

enum ConversationResult {
    case followUp(String)
    case complete(ParsedSession)
    case completeOffline(ParsedSession)  // Used when AI fails and backup parser succeeds
    case update(sessionNumber: Int, fields: [String: Any])
}

enum AISessionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case sessionNotFound(Int)
    case rateLimited
    case serviceUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key set — using offline parser"
        case .invalidResponse: return "Couldn't parse session from response"
        case .networkError(let e): return e.localizedDescription
        case .sessionNotFound(let n): return "Session #\(n) not found"
        case .rateLimited: return "Too many requests — please wait a moment and try again"
        case .serviceUnavailable(let msg): return msg
        }
    }

    var isFriendly: Bool {
        switch self {
        case .rateLimited, .serviceUnavailable: return true
        default: return false
        }
    }
}

// MARK: - Service

@MainActor
class AISessionService: ObservableObject {
    static let shared = AISessionService()
    
    private let urlSession = URLSession.shared
    private static let minimumInfoFollowUp = "I need one or two more details before I can log this. What stakes, venue, hours played, or session date should I use?"

    private init() {}
    
    // MARK: - Conversational parsing
    
    /// Routes to direct provider call if user has their own key, otherwise Worker proxy.
    func converse(
        messages: [ChatMessage],
        conversationId: String,
        workerBaseURL: String,
        geminiKey: String?,
        openAIKey: String?,
        existingSessions: String = ""
    ) async throws -> ConversationResult {
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else {
            throw AISessionError.invalidResponse
        }
        let referenceDate = Date()
        let recentMessages = Array(messages.suffix(8))
        do {
            let result: ConversationResult
            if let key = geminiKey, !key.isEmpty {
                result = try await converseWithGemini(messages: recentMessages, apiKey: key, existingSessions: existingSessions, referenceDate: referenceDate)
                return Self.normalize(result: result, from: lastUserMsg.text, relativeTo: referenceDate)
            }
            if let key = openAIKey, !key.isEmpty {
                result = try await converseWithOpenAI(messages: recentMessages, apiKey: key, existingSessions: existingSessions, referenceDate: referenceDate)
                return Self.normalize(result: result, from: lastUserMsg.text, relativeTo: referenceDate)
            }
            result = try await converseViaWorker(
                messages: recentMessages,
                conversationId: conversationId,
                workerBaseURL: workerBaseURL,
                existingSessions: existingSessions
            )
            return Self.normalize(result: result, from: lastUserMsg.text, relativeTo: referenceDate)
        } catch {
            if let offline = SessionParserService.parse(lastUserMsg.text, relativeTo: referenceDate) {
                guard Self.isLoggable(offline) else {
                    return .followUp(Self.minimumInfoFollowUp)
                }
                return .completeOffline(offline)
            }
            throw error
        }
    }
    
    // MARK: - System Prompt
    
    private func buildSystemPrompt(existingSessions: String, referenceDate: Date) -> String {
        let todayISO = ISO8601DateFormatter().string(from: referenceDate)
        let dayName = formatDayName(referenceDate)
        let dateContext = "Today is \(dayName). The current date in ISO 8601 is: \(todayISO). Use this as the ONLY reference when interpreting relative dates."

        let tagList = SessionTag.allCases.map { $0.rawValue }.joined(separator: ", ")

        var prompt = """
        You are a poker session logging assistant inside a tracking app. You help log new sessions and update existing ones.

        REFERENCE DATE (critical):
        \(dateContext)
        - Relative phrases like "last Saturday", "yesterday", "played last weekend", "this past Friday" MUST be computed relative to TODAY above.
        - The session date must always be in the recent past (within the last few weeks at most). Never output a date from years ago for relative phrases.

        CAPABILITIES:
        1. LOG NEW SESSION - gather info and return JSON to create a session
        2. UPDATE EXISTING SESSION - modify a session by its # number
        3. ASK FOR DETAILS - if user gives very minimal info, ask follow-up questions

        CRITICAL — AMOUNT EXTRACTION (READ CAREFULLY):
        - "amount" is the poker RESULT before off-table expenses like rake, tips, food, travel, or fees.
        - LOOK FOR KEYWORDS: "made", "won", "up", "lost", "down" followed by a dollar figure. That figure is the amount.
        - IGNORE peak/high-water-mark numbers. Words like "was up", "originally up", "peaked at" describe mid-session swings, NOT the final result.
        - EXAMPLE: "made 600 bucks ... was originally up 1200 but punted" → amount is 600 (NOT 1200). The 1200 is a mid-session peak. The "made 600" is what they took home. Put "Was originally up 1200 but punted" into notes.
        - EXAMPLE: "won 300 but was up 800 at one point" → amount is 300 (NOT 800).
        - EXAMPLE: "lost 500, was stuck 1000 earlier but fought back" → amount is -500.
        - If user says "bought in for X, cashed out for Y", compute amount as Y - X.
        - Treat compact amounts like "1k" = 1000 and "1.5k" = 1500.
        - Phrases like "in for 300, out for 850" mean amount = 550.
        - Positive amount = win, negative = loss.
        - WHEN IN DOUBT: use the number attached to "made/won/lost/down/up" at the START of the message, not numbers mentioned as past peaks.

        EXPENSES & FEES:
        - Track these separately when the user explicitly mentions them: rake, tips, food, travel, fees.
        - Always return expense values as POSITIVE numbers.
        - Examples:
          • "tipped 20" → tips = 20
          • "paid 15 in rake" or "time charge was 15" → rake = 15
          • "spent 12 on food" → food = 12
          • "uber was 18" or "travel cost 18" → travel = 18
          • "fees were 10" → fees = 10
        - Do NOT subtract expenses from amount yourself. The app calculates net bankroll impact as amount minus expenses.

        NOTES & HAND NOTES:
        - Any extra context the user provides beyond the core session data (amount, stakes, hours, venue, variant) should go into "notes".
        - Examples: "was on tilt", "table was really soft", "ran bad but played well", "was up 1200 but punted half back" — put these in "notes" as-is.
        - Do NOT ignore this context. Capture it faithfully.

        TAGS (strict rules):
        - Available tags: \(tagList)
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
        - If the user provides start/end times (e.g. "started at 7, ended at 11"), compute and return hoursPlayed from that range.
        - When you have enough info, respond with ONLY a JSON object:
          {"action": "create", "amount": number, "hoursPlayed": number|null, "stakes": string|null, "venue": string|null, "rake": number|null, "tips": number|null, "food": number|null, "travel": number|null, "fees": number|null, "gameFormat": string|null, "variant": string|null, "notes": string|null, "buyIn": number|null, "cashOut": number|null, "date": string|null, "tournamentPosition": number|null, "rebuys": number|null, "handNotes": string|null, "tags": [string]}
        - "date" must be ISO 8601 (YYYY-MM-DD or full ISO). If the user says "yesterday", "last Saturday", "played last weekend", etc., compute that date relative to TODAY and output it. Never use a date from a previous year for relative phrases.
        - Relative phrases like "last night", "Friday night", or "this morning" should also be resolved relative to TODAY above.
        - Default variant to "No Limit Hold'em" and format to "Cash Game" if not mentioned.

        RULES FOR UPDATES:
        - If the user says something like "update session 3" or "change session #5 stakes to 2/5", respond with:
          {"action": "update", "sessionNumber": number, "fields": {"fieldName": newValue, ...}}
        - Valid field names: amount, hoursPlayed, stakes, venue, rake, tips, food, travel, fees, gameFormat, variant, notes, buyIn, cashOut, date, tournamentPosition, rebuys, handNotes, tags
        - If the user wants to update but doesn't specify which session, ask them which session number.

        GENERAL RULES:
        - Keep responses SHORT and friendly. 1-2 sentences max for follow-ups.
        - Never wrap JSON in markdown code blocks. Return raw JSON only when creating/updating.
        - If you're asking a question (not creating/updating), respond with plain text only.
        """
        
        if !existingSessions.isEmpty {
            prompt += "\n\nEXISTING SESSIONS (for reference when updating):\n\(existingSessions)"
        }
        
        return prompt
    }
    
    // MARK: - Direct Gemini Conversation
    
    private static let geminiModelBasic = "gemini-2.5-flash-lite"
    private static let geminiModelAdvanced = "gemini-2.5-pro"
    private static let messageLengthThreshold = 250
    
    private static func pickGeminiModel(for messageLength: Int) -> String {
        messageLength > messageLengthThreshold ? geminiModelAdvanced : geminiModelBasic
    }
    
    private func converseWithGemini(messages: [ChatMessage], apiKey: String, existingSessions: String, referenceDate: Date) async throws -> ConversationResult {
        let userMsg = messages.last(where: { $0.role == .user })?.text ?? ""
        let model = Self.pickGeminiModel(for: userMsg.count)
        return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: model, referenceDate: referenceDate)
    }

    private func performGeminiCall(messages: [ChatMessage], apiKey: String, existingSessions: String, model: String, referenceDate: Date) async throws -> ConversationResult {
        var contents: [[String: Any]] = []
        for msg in messages {
            let role = msg.role == .user ? "user" : "model"
            contents.append(["role": role, "parts": [["text": msg.text]]])
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models/\(model):generateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AISessionError.serviceUnavailable("Invalid Gemini URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": buildSystemPrompt(existingSessions: existingSessions, referenceDate: referenceDate)]]],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 500
            ]
        ])

        let (data, response) = try await urlSession.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

        if httpStatus == 429, model == Self.geminiModelAdvanced {
            return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: Self.geminiModelBasic, referenceDate: referenceDate)
        }

        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = errorJson["error"] as? [String: Any],
           let message = error["message"] as? String {
            let isRateLimit = httpStatus == 429 || message.lowercased().contains("quota") || message.lowercased().contains("resource exhausted")
            if isRateLimit, model == Self.geminiModelAdvanced {
                return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: Self.geminiModelBasic, referenceDate: referenceDate)
            }
            throw AISessionError.networkError(NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AISessionError.invalidResponse
        }

        let responsePart = parts.last(where: { ($0["thought"] as? Bool) != true }) ?? parts.last
        guard let responseText = responsePart?["text"] as? String else {
            throw AISessionError.invalidResponse
        }

        let cleaned = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return classifyResponse(cleaned)
    }
    
    // MARK: - Direct OpenAI Conversation
    
    private func converseWithOpenAI(messages: [ChatMessage], apiKey: String, existingSessions: String, referenceDate: Date) async throws -> ConversationResult {
        var oaiMessages: [[String: String]] = [
            ["role": "system", "content": buildSystemPrompt(existingSessions: existingSessions, referenceDate: referenceDate)]
        ]
        for msg in messages {
            let role = msg.role == .user ? "user" : "assistant"
            oaiMessages.append(["role": role, "content": msg.text])
        }
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": oaiMessages,
            "temperature": 0.2,
            "max_tokens": 500
        ]
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AISessionError.serviceUnavailable("Invalid OpenAI URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await urlSession.data(for: request)
        
        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = errorJson["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AISessionError.networkError(NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AISessionError.invalidResponse
        }
        
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return classifyResponse(cleaned)
    }
    
    // MARK: - Worker proxy call
    
    private func converseViaWorker(messages: [ChatMessage], conversationId: String, workerBaseURL: String, existingSessions: String) async throws -> ConversationResult {
        guard let url = URL(string: "\(workerBaseURL)/v1/ai/session-crafter") else {
            throw AISessionError.serviceUnavailable("Invalid Worker URL")
        }
        
        let currentMessage = messages.last(where: { $0.role == .user })?.text ?? ""
        let history: [[String: String]] = Array(messages.dropLast()).suffix(5).map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "text": msg.text]
        }
        
        let body: [String: Any] = [
            "userId": AnonymousUserID.getOrCreate(),
            "conversationId": conversationId,
            "message": currentMessage,
            "history": history,
            "sessionContext": existingSessions
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AISessionError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 429 {
            throw AISessionError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let message = errObj["message"] as? String {
                throw AISessionError.serviceUnavailable(message)
            }
            throw AISessionError.serviceUnavailable("AI service error (HTTP \(httpResponse.statusCode))")
        }
        
        return try parseWorkerResponse(data)
    }
    
    // MARK: - Response Classification (direct provider path)
    
    private func classifyResponse(_ text: String) -> ConversationResult {
        guard text.hasPrefix("{"),
              let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .followUp(text)
        }
        
        let action = (parsed["action"] as? String ?? "create")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        if action == "update",
           let sessionNumber = Self.parseIntValue(parsed["sessionNumber"]),
           let fields = parsed["fields"] as? [String: Any] {
            return .update(sessionNumber: sessionNumber, fields: fields)
        }
        
        guard let amount = Self.parseDoubleValue(parsed["amount"]) else {
            return .followUp(text)
        }
        
        let hoursPlayed = Self.parseHoursFieldValue(parsed["hoursPlayed"])
        let stakes = Self.normalizedText(parsed["stakes"] as? String)
        let venue = VenueCleaner.clean(parsed["venue"] as? String)
        let rake = Self.parsePositiveDoubleValue(parsed["rake"])
        let tips = Self.parsePositiveDoubleValue(parsed["tips"])
        let food = Self.parsePositiveDoubleValue(parsed["food"])
        let travel = Self.parsePositiveDoubleValue(parsed["travel"])
        let fees = Self.parsePositiveDoubleValue(parsed["fees"])
        let notes = Self.normalizedText(parsed["notes"] as? String)
        let formatRaw = parsed["gameFormat"] as? String ?? parsed["gameType"] as? String ?? "Cash Game"
        let gameDetails = Self.resolvedGameDetails(formatValue: formatRaw, variantValue: parsed["variant"] as? String)
        let buyIn = Self.parseDoubleValue(parsed["buyIn"])
        let cashOut = Self.parseDoubleValue(parsed["cashOut"])
        let tournamentPosition = Self.parseIntValue(parsed["tournamentPosition"])
        let rebuys = Self.parseIntValue(parsed["rebuys"])
        let handNotes = Self.normalizedText(parsed["handNotes"] as? String)
        let tags = Self.normalizedTags(from: parsed["tags"])
        
        let date = (parsed["date"] as? String).flatMap { Self.parseDateString($0) }
        
        let session = ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
            rake: rake,
            tips: tips,
            food: food,
            travel: travel,
            fees: fees,
            gameType: gameDetails.gameType,
            variant: gameDetails.variant,
            notes: notes,
            buyIn: buyIn,
            cashOut: cashOut,
            date: date,
            tournamentPosition: tournamentPosition,
            rebuys: rebuys,
            handNotes: handNotes,
            tags: tags
        )
        guard Self.isLoggable(session) else {
            return .followUp(Self.minimumInfoFollowUp)
        }
        return .complete(session)
    }
    
    // MARK: - Worker response parsing
    
    private func parseWorkerResponse(_ data: Data) throws -> ConversationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultType = json["resultType"] as? String else {
            throw AISessionError.invalidResponse
        }
        
        let text = json["text"] as? String ?? ""
        
        switch resultType {
        case "followUp":
            return .followUp(text)
            
        case "complete":
            guard let sessionDict = json["parsedSession"] as? [String: Any] else {
                throw AISessionError.invalidResponse
            }
            let session = try Self.parsedSessionFromDict(sessionDict)
            return .complete(session)
            
        case "update":
            guard let updateDict = json["update"] as? [String: Any],
                  let sessionNumber = Self.parseIntValue(updateDict["sessionNumber"]),
                  let fields = updateDict["fields"] as? [String: Any] else {
                throw AISessionError.invalidResponse
            }
            return .update(sessionNumber: sessionNumber, fields: fields)
            
        default:
            return .followUp(text)
        }
    }
    
    private static func parsedSessionFromDict(_ d: [String: Any]) throws -> ParsedSession {
        guard let amount = parseDoubleValue(d["amount"]) else {
            throw AISessionError.invalidResponse
        }
        
        let hoursPlayed = parseHoursFieldValue(d["hoursPlayed"])
        let stakes = normalizedText(d["stakes"] as? String)
        let venue = VenueCleaner.clean(d["venue"] as? String)
        let rake = parsePositiveDoubleValue(d["rake"])
        let tips = parsePositiveDoubleValue(d["tips"])
        let food = parsePositiveDoubleValue(d["food"])
        let travel = parsePositiveDoubleValue(d["travel"])
        let fees = parsePositiveDoubleValue(d["fees"])
        let notes = normalizedText(d["notes"] as? String)
        let formatRaw = d["gameFormat"] as? String ?? d["gameType"] as? String ?? "Cash Game"
        let gameDetails = resolvedGameDetails(formatValue: formatRaw, variantValue: d["variant"] as? String)
        let buyIn = parseDoubleValue(d["buyIn"])
        let cashOut = parseDoubleValue(d["cashOut"])
        let tournamentPosition = parseIntValue(d["tournamentPosition"])
        let rebuys = parseIntValue(d["rebuys"])
        let handNotes = normalizedText(d["handNotes"] as? String)
        let tags = normalizedTags(from: d["tags"])
        
        let date = (d["date"] as? String).flatMap { parseDateString($0) }
        
        return ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
            rake: rake,
            tips: tips,
            food: food,
            travel: travel,
            fees: fees,
            gameType: gameDetails.gameType,
            variant: gameDetails.variant,
            notes: notes,
            buyIn: buyIn,
            cashOut: cashOut,
            date: date,
            tournamentPosition: tournamentPosition,
            rebuys: rebuys,
            handNotes: handNotes,
            tags: tags
        )
    }
    
    // MARK: - Helpers

    static func isLoggable(_ session: ParsedSession) -> Bool {
        if !session.amount.isFinite { return false }
        let hasSupportingDetail =
            session.hoursPlayed != nil ||
            hasText(session.stakes) ||
            hasText(session.venue) ||
            hasText(session.notes) ||
            hasText(session.variant) ||
            session.gameType != .cash ||
            session.rake != nil ||
            session.tips != nil ||
            session.food != nil ||
            session.travel != nil ||
            session.fees != nil ||
            session.buyIn != nil ||
            session.cashOut != nil ||
            session.date != nil ||
            session.tournamentPosition != nil ||
            session.rebuys != nil ||
            hasText(session.handNotes) ||
            !session.tags.isEmpty
        return hasSupportingDetail
    }

    static func minimumInfoFollowUpMessage() -> String {
        minimumInfoFollowUp
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalize(result: ConversationResult, from message: String, relativeTo referenceDate: Date) -> ConversationResult {
        let recoveredDate = recoverDateOnlyFollowUp(in: result, from: message, relativeTo: referenceDate)
        let recoveredOffline = recoverOfflineCompletion(in: recoveredDate, from: message, relativeTo: referenceDate)
        return mergeMissingFields(in: recoveredOffline, from: message, relativeTo: referenceDate)
    }

    private static func recoverDateOnlyFollowUp(in result: ConversationResult, from message: String, relativeTo referenceDate: Date) -> ConversationResult {
        guard case .followUp(let text) = result,
              let recoveredDate = parseDateString(text),
              let offlineSession = SessionParserService.parse(message, relativeTo: referenceDate) else {
            return result
        }
        return .complete(offlineSession.withDate(recoveredDate))
    }

    private static func recoverOfflineCompletion(in result: ConversationResult, from message: String, relativeTo referenceDate: Date) -> ConversationResult {
        guard case .followUp = result,
              let offline = SessionParserService.parse(message, relativeTo: referenceDate),
              isLoggable(offline) else {
            return result
        }
        return .completeOffline(offline)
    }

    private static func mergeMissingFields(in result: ConversationResult, from message: String, relativeTo referenceDate: Date) -> ConversationResult {
        guard let signals = SessionParserService.extractSignals(from: message, relativeTo: referenceDate) else {
            return result
        }

        switch result {
        case .complete(let session):
            return .complete(session.mergingMissingFields(from: signals))
        case .completeOffline(let session):
            return .completeOffline(session.mergingMissingFields(from: signals))
        case .update(let sessionNumber, var fields):
            if fields["hoursPlayed"] == nil, let hours = signals.hoursPlayed {
                fields["hoursPlayed"] = hours
            }
            if fields["stakes"] == nil, let stakes = signals.stakes {
                fields["stakes"] = stakes
            }
            if fields["venue"] == nil, let venue = signals.venue {
                fields["venue"] = venue
            }
            if fields["rake"] == nil, let rake = signals.rake {
                fields["rake"] = rake
            }
            if fields["tips"] == nil, let tips = signals.tips {
                fields["tips"] = tips
            }
            if fields["food"] == nil, let food = signals.food {
                fields["food"] = food
            }
            if fields["travel"] == nil, let travel = signals.travel {
                fields["travel"] = travel
            }
            if fields["fees"] == nil, let fees = signals.fees {
                fields["fees"] = fees
            }
            if fields["variant"] == nil, let variant = signals.variant {
                fields["variant"] = variant
            }
            if fields["buyIn"] == nil, let buyIn = signals.buyIn {
                fields["buyIn"] = buyIn
            }
            if fields["cashOut"] == nil, let cashOut = signals.cashOut {
                fields["cashOut"] = cashOut
            }
            if fields["tournamentPosition"] == nil, let position = signals.tournamentPosition {
                fields["tournamentPosition"] = position
            }
            if fields["rebuys"] == nil, let rebuys = signals.rebuys {
                fields["rebuys"] = rebuys
            }
            if fields["date"] == nil, let date = signals.date {
                fields["date"] = formatDateString(date)
            }
            if fields["gameFormat"] == nil, fields["gameType"] == nil, let gameType = signals.gameType {
                fields["gameFormat"] = gameType.rawValue
            }
            return .update(sessionNumber: sessionNumber, fields: fields)
        case .followUp:
            return result
        }
    }

    private static func parseDateString(_ dateStr: String) -> Date? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }

        let formats = [
            "yyyy-MM-dd",
            "M/d/yyyy",
            "M/d/yy",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d yyyy",
            "MMMM d yyyy"
        ]

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone.current
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: trimmed) {
                return date
            }
        }

        return SessionParserService.parseDateValue(from: trimmed)
    }

    private static func formatDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parseDoubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let n as NSNumber:
            guard !isBooleanNumber(n) else { return nil }
            return n.doubleValue
        case let s as String:
            return SessionParserService.parseNumericValue(from: s)
        default:
            return nil
        }
    }

    private static func parseHoursFieldValue(_ value: Any?) -> Double? {
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let duration = SessionParserService.parseHoursValue(from: trimmed) {
                return duration
            }
            return SessionParserService.parseNumericValue(from: trimmed)
        }
        return parseDoubleValue(value)
    }

    static func parsePositiveDoubleValue(_ value: Any?) -> Double? {
        guard let value = parseDoubleValue(value) else { return nil }
        let normalized = abs(value)
        return normalized > 0.0001 ? normalized : nil
    }

    static func parseIntValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int:
            return i
        case let d as Double:
            return exactInteger(from: d)
        case let n as NSNumber:
            guard !isBooleanNumber(n) else { return nil }
            return exactInteger(from: n.doubleValue)
        case let s as String:
            return SessionParserService.parseWholeNumberValue(from: s)
        default:
            return nil
        }
    }

    private static func exactInteger(from value: Double) -> Int? {
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(Int.min),
              value <= Double(Int.max) else {
            return nil
        }
        return Int(value)
    }

    private static func isBooleanNumber(_ value: NSNumber) -> Bool {
        CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    private static func normalizedGameType(from value: Any?) -> GameType? {
        guard let rawValue = value as? String else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = GameType.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact == .plo ? .cash : exact
        }
        if let parsed = SessionParserService.parseGameTypeValue(from: trimmed) {
            return parsed == .plo ? .cash : parsed
        }

        switch comparableToken(for: trimmed) {
        case "cash", "cashgame", "ringgame":
            return .cash
        case "plo":
            return .cash
        case "tournament", "mtt":
            return .tournament
        case "sitgo", "sitandgo", "sitngo", "sng", "spingo", "spinandgo":
            return .sitAndGo
        case "homegame":
            return .homeGame
        case "online":
            return .online
        default:
            return nil
        }
    }

    private static func resolvedGameDetails(formatValue: Any?, variantValue: String?) -> (gameType: GameType, variant: String?) {
        let resolvedVariant = normalizedVariant(variantValue)
        let gameType = normalizedGameType(from: formatValue) ?? .cash
        guard isLegacyPLOGameType(formatValue) else {
            return (gameType, resolvedVariant)
        }
        return (.cash, resolvedVariant ?? PokerVariant.plo.rawValue)
    }

    private static func isLegacyPLOGameType(_ value: Any?) -> Bool {
        guard let rawValue = value as? String else { return false }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let exact = GameType.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact == .plo
        }
        if let parsed = SessionParserService.parseGameTypeValue(from: trimmed) {
            return parsed == .plo
        }
        return comparableToken(for: trimmed) == "plo"
    }

    private static func normalizedVariant(_ value: String?) -> String? {
        guard let trimmed = normalizedText(value) else { return nil }
        if let exact = PokerVariant.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.rawValue
        }
        if let parsed = SessionParserService.parseVariantValue(from: trimmed) {
            return parsed
        }
        return trimmed
    }
    
    private func formatDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    /// Builds a compact summary string of sessions for the AI context.
    static func buildSessionContext(from sessions: [PokerSession], currency: String = "USD") -> String {
        guard !sessions.isEmpty else { return "" }
        let sorted = sessions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        let lines = sorted.enumerated().map { index, s -> String in
            let num = index + 1
            let df = DateFormatter()
            df.dateFormat = "M/d/yy"
            let dateStr = df.string(from: s.date)
            let netAmountStr = PokerSession.formatCurrency(s.netAmount, currency: currency)
            var detail = "#\(num): net \(netAmountStr) on \(dateStr)"
            if s.hasExpenses {
                detail += " (gross \(PokerSession.formatCurrency(s.amount, currency: currency)), expenses \(PokerSession.formatCurrency(s.totalExpenses, currency: currency)))"
            }
            if let stakes = s.stakes { detail += ", \(stakes)" }
            detail += ", \(s.displayVariant)"
            if let venue = s.venue { detail += " at \(venue)" }
            if let hours = s.hoursPlayed { detail += ", \(String(format: "%.1f", hours))h" }
            return detail
        }
        return lines.joined(separator: "\n")
    }
    
    /// Applies update fields to an existing session
    static func applyUpdate(to session: PokerSession, fields: [String: Any]) -> PokerSession {
        var s = session
        let explicitVariantField = fields.keys.contains("variant")
        if fieldIsNull(fields["hoursPlayed"]) { s.hoursPlayed = nil }
        if let amount = parseDoubleValue(fields["amount"]) { s.amount = amount }
        if let hours = parseHoursFieldValue(fields["hoursPlayed"]) { s.hoursPlayed = hours }
        if fieldIsNull(fields["stakes"]) { s.stakes = nil }
        if let stakes = fields["stakes"] as? String { s.stakes = normalizedText(stakes) }
        if fieldIsNull(fields["venue"]) { s.venue = nil }
        if let raw = fields["venue"] as? String { s.venue = VenueCleaner.clean(raw) }
        if fieldIsNull(fields["rake"]) || shouldClearPositiveOptional(fields["rake"]) { s.rake = nil }
        if let rake = parsePositiveDoubleValue(fields["rake"]) { s.rake = rake }
        if fieldIsNull(fields["tips"]) || shouldClearPositiveOptional(fields["tips"]) { s.tips = nil }
        if let tips = parsePositiveDoubleValue(fields["tips"]) { s.tips = tips }
        if fieldIsNull(fields["food"]) || shouldClearPositiveOptional(fields["food"]) { s.food = nil }
        if let food = parsePositiveDoubleValue(fields["food"]) { s.food = food }
        if fieldIsNull(fields["travel"]) || shouldClearPositiveOptional(fields["travel"]) { s.travel = nil }
        if let travel = parsePositiveDoubleValue(fields["travel"]) { s.travel = travel }
        if fieldIsNull(fields["fees"]) || shouldClearPositiveOptional(fields["fees"]) { s.fees = nil }
        if let fees = parsePositiveDoubleValue(fields["fees"]) { s.fees = fees }
        if fieldIsNull(fields["notes"]) { s.notes = "" }
        if let notes = fields["notes"] as? String { s.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines) }
        if fieldIsNull(fields["variant"]) { s.variant = nil }
        if let variant = fields["variant"] as? String { s.variant = normalizedVariant(variant) }
        if fieldIsNull(fields["buyIn"]) { s.buyIn = nil }
        if let buyIn = parseDoubleValue(fields["buyIn"]) { s.buyIn = buyIn }
        if fieldIsNull(fields["cashOut"]) { s.cashOut = nil }
        if let cashOut = parseDoubleValue(fields["cashOut"]) { s.cashOut = cashOut }
        if fieldIsNull(fields["tournamentPosition"]) { s.tournamentPosition = nil }
        if let pos = parseIntValue(fields["tournamentPosition"]) { s.tournamentPosition = pos }
        if fieldIsNull(fields["rebuys"]) { s.rebuys = nil }
        if let rebuys = parseIntValue(fields["rebuys"]) { s.rebuys = rebuys }
        if fieldIsNull(fields["handNotes"]) { s.handNotes = nil }
        if let handNotes = fields["handNotes"] as? String { s.handNotes = normalizedText(handNotes) }
        if fieldIsNull(fields["tags"]) { s.tags = [] }
        if fields.keys.contains("tags"), !fieldIsNull(fields["tags"]) {
            s.tags = normalizedTags(from: fields["tags"])
        }
        let rawGameType = (fields["gameFormat"] as? String) ?? (fields["gameType"] as? String)
        if let gameType = normalizedGameType(from: rawGameType) {
            s.gameType = gameType
        }
        if isLegacyPLOGameType(rawGameType) {
            if !explicitVariantField || normalizedText(fields["variant"] as? String) == nil {
                s.variant = PokerVariant.plo.rawValue
            }
        }
        if let dateStr = fields["date"] as? String {
            if let d = parseDateString(dateStr) { s.date = d }
        }
        return s
    }

    private static func fieldIsNull(_ value: Any?) -> Bool {
        value is NSNull
    }

    private static func shouldClearPositiveOptional(_ value: Any?) -> Bool {
        guard let numeric = parseDoubleValue(value) else { return false }
        return abs(numeric) <= 0.0001
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedTags(from value: Any?) -> [String] {
        let rawTags: [String]
        switch value {
        case let tags as [String]:
            rawTags = tags
        case let tags as [Any]:
            rawTags = tags.compactMap { $0 as? String }
        case let tag as String:
            rawTags = tag.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }).map(String.init)
        default:
            return []
        }

        var seen = Set<String>()
        var orderedTags: [String] = []

        for rawTag in rawTags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalizedToken = comparableToken(for: trimmed)
            guard let normalized = SessionTag.allCases.first(where: { comparableToken(for: $0.rawValue) == normalizedToken })?.rawValue else {
                continue
            }
            guard seen.insert(normalizedToken).inserted else { continue }
            orderedTags.append(normalized)
        }

        return orderedTags
    }

    private static func comparableToken(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
