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
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String
    
    enum Role: Equatable {
        case user
        case assistant
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
        let current = [lastUserMsg]
        do {
            let result: ConversationResult
            if let key = geminiKey, !key.isEmpty {
                result = try await converseWithGemini(messages: current, apiKey: key, existingSessions: existingSessions)
                return Self.inferMissingHours(in: result, from: lastUserMsg.text)
            }
            if let key = openAIKey, !key.isEmpty {
                result = try await converseWithOpenAI(messages: current, apiKey: key, existingSessions: existingSessions)
                return Self.inferMissingHours(in: result, from: lastUserMsg.text)
            }
            result = try await converseViaWorker(
                messages: current,
                conversationId: conversationId,
                workerBaseURL: workerBaseURL,
                existingSessions: existingSessions
            )
            return Self.inferMissingHours(in: result, from: lastUserMsg.text)
        } catch {
            if let offline = SessionParserService.parse(lastUserMsg.text) {
                guard Self.isLoggable(offline) else {
                    return .followUp(Self.minimumInfoFollowUp)
                }
                return .completeOffline(offline)
            }
            throw error
        }
    }
    
    // MARK: - System Prompt
    
    private func buildSystemPrompt(existingSessions: String) -> String {
        let now = Date()
        let todayISO = ISO8601DateFormatter().string(from: now)
        let dayName = formatDayName(now)
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
    
    private func converseWithGemini(messages: [ChatMessage], apiKey: String, existingSessions: String) async throws -> ConversationResult {
        let userMsg = messages.last(where: { $0.role == .user })?.text ?? ""
        let model = Self.pickGeminiModel(for: userMsg.count)
        return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: model)
    }

    private func performGeminiCall(messages: [ChatMessage], apiKey: String, existingSessions: String, model: String) async throws -> ConversationResult {
        var contents: [[String: Any]] = []
        for msg in messages {
            let role = msg.role == .user ? "user" : "model"
            contents.append(["role": role, "parts": [["text": msg.text]]])
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": buildSystemPrompt(existingSessions: existingSessions)]]],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 500
            ]
        ])

        let (data, response) = try await urlSession.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

        if httpStatus == 429, model == Self.geminiModelAdvanced {
            return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: Self.geminiModelBasic)
        }

        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = errorJson["error"] as? [String: Any],
           let message = error["message"] as? String {
            let isRateLimit = httpStatus == 429 || message.lowercased().contains("quota") || message.lowercased().contains("resource exhausted")
            if isRateLimit, model == Self.geminiModelAdvanced {
                return try await performGeminiCall(messages: messages, apiKey: apiKey, existingSessions: existingSessions, model: Self.geminiModelBasic)
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
    
    private func converseWithOpenAI(messages: [ChatMessage], apiKey: String, existingSessions: String) async throws -> ConversationResult {
        var oaiMessages: [[String: String]] = [
            ["role": "system", "content": buildSystemPrompt(existingSessions: existingSessions)]
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
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
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
        
        let action = parsed["action"] as? String ?? "create"
        
        if action == "update",
           let sessionNumber = Self.parseIntValue(parsed["sessionNumber"]),
           let fields = parsed["fields"] as? [String: Any] {
            return .update(sessionNumber: sessionNumber, fields: fields)
        }
        
        guard let amount = Self.parseDoubleValue(parsed["amount"]) else {
            return .followUp(text)
        }
        
        let hoursPlayed = Self.parseDoubleValue(parsed["hoursPlayed"])
        let stakes = parsed["stakes"] as? String
        let venue = VenueCleaner.clean(parsed["venue"] as? String)
        let notes = parsed["notes"] as? String
        let variant = parsed["variant"] as? String
        let formatRaw = parsed["gameFormat"] as? String ?? parsed["gameType"] as? String ?? "Cash Game"
        let gameType = GameType(rawValue: formatRaw) ?? .cash
        let buyIn = Self.parseDoubleValue(parsed["buyIn"])
        let cashOut = Self.parseDoubleValue(parsed["cashOut"])
        let tournamentPosition = Self.parseIntValue(parsed["tournamentPosition"])
        let rebuys = Self.parseIntValue(parsed["rebuys"])
        let handNotes = parsed["handNotes"] as? String
        let tags = (parsed["tags"] as? [String]) ?? []
        
        var date: Date?
        if let dateStr = parsed["date"] as? String {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = fmt.date(from: dateStr)
            if date == nil {
                let fmt2 = ISO8601DateFormatter()
                date = fmt2.date(from: dateStr)
            }
            if date == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                date = df.date(from: dateStr)
            }
        }
        
        let session = ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
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
        
        let hoursPlayed = parseDoubleValue(d["hoursPlayed"])
        let stakes = d["stakes"] as? String
        let venue = VenueCleaner.clean(d["venue"] as? String)
        let notes = d["notes"] as? String
        let variant = d["variant"] as? String
        let formatRaw = d["gameFormat"] as? String ?? d["gameType"] as? String ?? "Cash Game"
        let gameType = GameType(rawValue: formatRaw) ?? .cash
        let buyIn = parseDoubleValue(d["buyIn"])
        let cashOut = parseDoubleValue(d["cashOut"])
        let tournamentPosition = parseIntValue(d["tournamentPosition"])
        let rebuys = parseIntValue(d["rebuys"])
        let handNotes = d["handNotes"] as? String
        let tags = (d["tags"] as? [String]) ?? []
        
        var date: Date?
        if let dateStr = d["date"] as? String {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = fmt.date(from: dateStr)
            if date == nil {
                let fmt2 = ISO8601DateFormatter()
                date = fmt2.date(from: dateStr)
            }
            if date == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                date = df.date(from: dateStr)
            }
        }
        
        return ParsedSession(
            amount: amount,
            hoursPlayed: hoursPlayed,
            stakes: stakes,
            venue: venue,
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
    
    // MARK: - Helpers

    static func isLoggable(_ session: ParsedSession) -> Bool {
        if !session.amount.isFinite { return false }
        let hasSupportingDetail =
            session.hoursPlayed != nil ||
            hasText(session.stakes) ||
            hasText(session.venue) ||
            hasText(session.notes) ||
            hasText(session.variant) ||
            session.buyIn != nil ||
            session.cashOut != nil ||
            session.date != nil ||
            session.tournamentPosition != nil ||
            session.rebuys != nil ||
            hasText(session.handNotes)
        return hasSupportingDetail
    }

    static func minimumInfoFollowUpMessage() -> String {
        minimumInfoFollowUp
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func inferMissingHours(in result: ConversationResult, from message: String) -> ConversationResult {
        guard let inferredHours = SessionParserService.parseHoursValue(from: message) else { return result }
        switch result {
        case .complete(let session):
            guard session.hoursPlayed == nil else { return result }
            return .complete(session.withHoursPlayed(inferredHours))
        case .completeOffline(let session):
            guard session.hoursPlayed == nil else { return result }
            return .completeOffline(session.withHoursPlayed(inferredHours))
        case .update(let sessionNumber, var fields):
            guard parseDoubleValue(fields["hoursPlayed"]) == nil else { return result }
            fields["hoursPlayed"] = inferredHours
            return .update(sessionNumber: sessionNumber, fields: fields)
        case .followUp:
            return result
        }
    }

    static func parseDoubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let n as NSNumber:
            return n.doubleValue
        case let s as String:
            let cleaned = s
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        default:
            return nil
        }
    }

    static func parseIntValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int:
            return i
        case let d as Double:
            return Int(d)
        case let n as NSNumber:
            return n.intValue
        case let s as String:
            return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
    
    private func formatDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    /// Builds a compact summary string of sessions for the AI context.
    static func buildSessionContext(from sessions: [PokerSession], currency: String = "USD") -> String {
        guard !sessions.isEmpty else { return "" }
        let sorted = sessions.sorted { $0.date < $1.date }
        let lines = sorted.prefix(50).enumerated().map { index, s -> String in
            let num = index + 1
            let df = DateFormatter()
            df.dateFormat = "M/d/yy"
            let dateStr = df.string(from: s.date)
            let amountStr = PokerSession.formatCurrency(s.amount, currency: currency)
            var detail = "#\(num): \(amountStr) on \(dateStr)"
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
        if let amount = parseDoubleValue(fields["amount"]) { s.amount = amount }
        if let hours = parseDoubleValue(fields["hoursPlayed"]) { s.hoursPlayed = hours }
        if let stakes = fields["stakes"] as? String { s.stakes = stakes }
        if let raw = fields["venue"] as? String { s.venue = VenueCleaner.clean(raw) }
        if let notes = fields["notes"] as? String { s.notes = notes }
        if let variant = fields["variant"] as? String { s.variant = variant }
        if let buyIn = parseDoubleValue(fields["buyIn"]) { s.buyIn = buyIn }
        if let cashOut = parseDoubleValue(fields["cashOut"]) { s.cashOut = cashOut }
        if let pos = parseIntValue(fields["tournamentPosition"]) { s.tournamentPosition = pos }
        if let rebuys = parseIntValue(fields["rebuys"]) { s.rebuys = rebuys }
        if let handNotes = fields["handNotes"] as? String { s.handNotes = handNotes }
        if let formatRaw = fields["gameFormat"] as? String,
           let gameType = GameType(rawValue: formatRaw) { s.gameType = gameType }
        if let dateStr = fields["date"] as? String {
            let fmt = ISO8601DateFormatter()
            if let d = fmt.date(from: dateStr) { s.date = d }
            else {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                if let d = df.date(from: dateStr) { s.date = d }
            }
        }
        return s
    }
}
