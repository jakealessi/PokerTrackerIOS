//
//  APIKeysLoader.swift
//  PokerTrackerIOS
//
//  Loads API keys from APIKeys.plist (gitignored - never committed).
//  Copy APIKeys.example.plist to APIKeys.plist and add your keys.
//

import Foundation

enum APIKeysLoader {
    private static let placeholderGemini = "your-gemini-key-here"
    private static let placeholderOpenAI = "your-openai-key-here"
    
    static var geminiKey: String? {
        guard let key = loadFromPlist(key: "GeminiAPIKey"),
              !key.isEmpty,
              key != placeholderGemini else { return nil }
        return key
    }
    
    static var openAIKey: String? {
        guard let key = loadFromPlist(key: "OpenAIAPIKey"),
              !key.isEmpty,
              key != placeholderOpenAI else { return nil }
        return key
    }
    
    private static func loadFromPlist(key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "APIKeys", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String else { return nil }
        return value
    }
}
