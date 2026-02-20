//
//  AISessionService.swift
//  PokerTrackerIOS
//
//  Conversational AI session logging via Gemini or OpenAI.
//  Supports creating new sessions and updating existing ones by session number.
//  Falls back to offline regex parser if API fails.
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
}

struct ParseResult {
    let session: ParsedSession
    let usedFallback: Bool
    let fallbackReason: String?
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
    case update(sessionNumber: Int, fields: [String: Any])
}

enum AISessionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case sessionNotFound(Int)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key set — using offline parser"
        case .invalidResponse: return "Couldn't parse session from response"
        case .networkError(let e): return e.localizedDescription
        case .sessionNotFound(let n): return "Session #\(n) not found"
        }
    }
}

// MARK: - Service

@MainActor
class AISessionService: ObservableObject {
    static let shared = AISessionService()
    
    private let session = URLSession.shared
    /// Default Gemini key for out-of-box AI. Repo is private; users can override in Settings or APIKeys.plist.
    private static let defaultGeminiKey = "AIzaSyCXw4GbAU_V9nV1hLtk0aLjyhljYoa1Hvs"

    private init() {}
    
    // MARK: - Conversational parsing
    
    func converse(messages: [ChatMessage], geminiKey: String?, openAIKey: String?, existingSessions: String = "") async throws -> ConversationResult {
        let resolvedGemini = geminiKey ?? APIKeysLoader.geminiKey ?? Self.defaultGeminiKey
        
        do {
            if !resolvedGemini.isEmpty {
                return try await converseWithGemini(messages: messages, apiKey: resolvedGemini, existingSessions: existingSessions)
            }
            if let key = openAIKey, !key.isEmpty {
                return try await converseWithOpenAI(messages: messages, apiKey: key, existingSessions: existingSessions)
            }
        } catch {
            let allUserText = messages.filter { $0.role == .user }.map { $0.text }.joined(separator: " ")
            if let offline = SessionParserService.parse(allUserText) {
                return .complete(offline)
            }
            throw error
        }
        
        let allUserText = messages.filter { $0.role == .user }.map { $0.text }.joined(separator: " ")
        if let offline = SessionParserService.parse(allUserText) {
            return .complete(offline)
        }
        throw AISessionError.noAPIKey
    }
    
    // MARK: - Single-shot parsing
    
    func parseSession(from description: String, geminiKey: String?, openAIKey: String?) async throws -> ParseResult {
        let resolvedGemini = geminiKey ?? APIKeysLoader.geminiKey ?? Self.defaultGeminiKey
        
        do {
            if !resolvedGemini.isEmpty {
                let parsed = try await parseWithGemini(from: description, apiKey: resolvedGemini)
                return ParseResult(session: parsed, usedFallback: false, fallbackReason: nil)
            }
            if let key = openAIKey, !key.isEmpty {
                let parsed = try await parseWithOpenAI(from: description, apiKey: key)
                return ParseResult(session: parsed, usedFallback: false, fallbackReason: nil)
            }
        } catch {
            if let offline = SessionParserService.parse(description) {
                let reason = "AI failed: \(error.localizedDescription). Used offline parser."
                return ParseResult(session: offline, usedFallback: true, fallbackReason: reason)
            }
            throw error
        }
        
        if let offline = SessionParserService.parse(description) {
            return ParseResult(session: offline, usedFallback: true, fallbackReason: "No API key — used offline parser.")
        }
        throw AISessionError.noAPIKey
    }
    
    // MARK: - System Prompt
    
    private func buildSystemPrompt(existingSessions: String) -> String {
        let now = Date()
        let todayISO = ISO8601DateFormatter().string(from: now)
        let dayName = formatDayName(now)
        // e.g. "Today is Monday, February 17, 2025. Use this as the ONLY reference for relative dates."
        let dateContext = "Today is \(dayName). The current date in ISO 8601 is: \(todayISO). Use this as the ONLY reference when interpreting relative dates."

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

        RULES FOR NEW SESSIONS:
        - If the user gives ONLY an amount (e.g. "won 50" or "lost 200") with no other details, ask a SHORT friendly question to get more info. Ask about 2-3 things at once (like stakes, game type, hours, venue).
        - If the user provides an amount PLUS at least one other detail (stakes, venue, hours, game type, etc.), go ahead and log it.
        - When you have enough info, respond with ONLY a JSON object:
          {"action": "create", "amount": number, "hoursPlayed": number|null, "stakes": string|null, "venue": string|null, "gameFormat": string|null, "variant": string|null, "notes": string|null, "buyIn": number|null, "cashOut": number|null, "date": string|null, "tournamentPosition": number|null, "rebuys": number|null, "handNotes": string|null}
        - "date" must be ISO 8601 (YYYY-MM-DD or full ISO). If the user says "yesterday", "last Saturday", "played last weekend", etc., compute that date relative to TODAY and output it. Never use a date from a previous year for relative phrases.
        - Positive amount = win, negative = loss.
        - If user says "bought in for X, cashed out for Y", compute amount as Y - X.
        - Default variant to "No Limit Hold'em" and format to "Cash Game" if not mentioned.

        RULES FOR UPDATES:
        - If the user says something like "update session 3" or "change session #5 stakes to 2/5", respond with:
          {"action": "update", "sessionNumber": number, "fields": {"fieldName": newValue, ...}}
        - Valid field names: amount, hoursPlayed, stakes, venue, gameFormat, variant, notes, buyIn, cashOut, date, tournamentPosition, rebuys, handNotes
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
    
    // MARK: - Gemini Conversation
    
    private func converseWithGemini(messages: [ChatMessage], apiKey: String, existingSessions: String) async throws -> ConversationResult {
        var contents: [[String: Any]] = []
        
        for msg in messages {
            let role = msg.role == .user ? "user" : "model"
            contents.append(["role": role, "parts": [["text": msg.text]]])
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=\(apiKey)")!
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
        
        let (data, _) = try await session.data(for: request)
        
        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = errorJson["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AISessionError.networkError(NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            throw AISessionError.invalidResponse
        }
        
        let cleaned = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return classifyResponse(cleaned)
    }
    
    // MARK: - OpenAI Conversation
    
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
        
        let (data, _) = try await session.data(for: request)
        
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
    
    // MARK: - Response Classification
    
    private func classifyResponse(_ text: String) -> ConversationResult {
        guard text.hasPrefix("{"),
              let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .followUp(text)
        }
        
        let action = parsed["action"] as? String ?? "create"
        
        if action == "update",
           let sessionNumber = parsed["sessionNumber"] as? Int,
           let fields = parsed["fields"] as? [String: Any] {
            return .update(sessionNumber: sessionNumber, fields: fields)
        }
        
        // Create action
        guard let amount = parsed["amount"] as? Double else {
            return .followUp(text)
        }
        
        let hoursPlayed = parsed["hoursPlayed"] as? Double
        let stakes = parsed["stakes"] as? String
        let venue = VenueCleaner.clean(parsed["venue"] as? String)
        let notes = parsed["notes"] as? String
        let variant = parsed["variant"] as? String
        let formatRaw = parsed["gameFormat"] as? String ?? parsed["gameType"] as? String ?? "Cash Game"
        let gameType = GameType(rawValue: formatRaw) ?? .cash
        let buyIn = parsed["buyIn"] as? Double
        let cashOut = parsed["cashOut"] as? Double
        let tournamentPosition = parsed["tournamentPosition"] as? Int
        let rebuys = parsed["rebuys"] as? Int
        let handNotes = parsed["handNotes"] as? String
        
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
            handNotes: handNotes
        )
        return .complete(session)
    }
    
    // MARK: - Single-shot helpers
    
    private func parseWithGemini(from description: String, apiKey: String) async throws -> ParsedSession {
        let messages = [ChatMessage(role: .user, text: description)]
        let result = try await converseWithGemini(messages: messages, apiKey: apiKey, existingSessions: "")
        switch result {
        case .complete(let session): return session
        case .followUp, .update: throw AISessionError.invalidResponse
        }
    }
    
    private func parseWithOpenAI(from description: String, apiKey: String) async throws -> ParsedSession {
        let messages = [ChatMessage(role: .user, text: description)]
        let result = try await converseWithOpenAI(messages: messages, apiKey: apiKey, existingSessions: "")
        switch result {
        case .complete(let session): return session
        case .followUp, .update: throw AISessionError.invalidResponse
        }
    }
    
    // MARK: - Helpers
    
    /// e.g. "Monday, February 17, 2025"
    private func formatDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    /// Builds a compact summary string of sessions for the AI context.
    /// Numbers are dynamic: earliest = #1, next = #2, etc.
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
        if let amount = fields["amount"] as? Double { s.amount = amount }
        if let hours = fields["hoursPlayed"] as? Double { s.hoursPlayed = hours }
        if let stakes = fields["stakes"] as? String { s.stakes = stakes }
        if let raw = fields["venue"] as? String { s.venue = VenueCleaner.clean(raw) }
        if let notes = fields["notes"] as? String { s.notes = notes }
        if let variant = fields["variant"] as? String { s.variant = variant }
        if let buyIn = fields["buyIn"] as? Double { s.buyIn = buyIn }
        if let cashOut = fields["cashOut"] as? Double { s.cashOut = cashOut }
        if let pos = fields["tournamentPosition"] as? Int { s.tournamentPosition = pos }
        if let rebuys = fields["rebuys"] as? Int { s.rebuys = rebuys }
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
