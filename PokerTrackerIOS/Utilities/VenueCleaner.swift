//
//  VenueCleaner.swift
//  PokerTrackerIOS
//

import UIKit

enum VenueCleaner {
    /// Cleans parsed venue: trims, capitalizes, optionally spell-corrects
    static func clean(_ venue: String?) -> String? {
        let trimmed = venue?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""
        guard !trimmed.isEmpty else { return nil }
        let shouldNormalizeCase = trimmed == trimmed.lowercased()
        var s = shouldNormalizeCase ? titleCase(trimmed) : trimmed
        // Only spell-correct when input was all lowercase (likely a typo, not proper noun)
        if shouldNormalizeCase, let corrected = spellCorrect(s), corrected != s {
            s = corrected
        }
        return s.isEmpty ? nil : s
    }

    static func key(for venue: String?) -> String? {
        guard let cleaned = clean(venue) else { return nil }
        return cleaned
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    static func normalizedList(_ venues: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for venue in venues {
            guard let cleaned = clean(venue), let key = key(for: cleaned) else { continue }
            guard seen.insert(key).inserted else { continue }
            normalized.append(cleaned)
        }

        return normalized
    }
    
    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ")
            .map { word in
                let str = String(word)
                guard let first = str.first else { return str }
                return String(first).uppercased() + str.dropFirst()
            }
            .joined(separator: " ")
    }
    
    private static func spellCorrect(_ s: String) -> String? {
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: s.utf16.count)
        let misspelledRange = checker.rangeOfMisspelledWord(in: s, range: range, startingAt: 0, wrap: false, language: "en")
        guard misspelledRange.location != NSNotFound,
              let replacement = (checker.guesses(forWordRange: misspelledRange, in: s, language: "en") ?? []).first,
              let start = Range(misspelledRange, in: s) else { return nil }
        var result = s
        result.replaceSubrange(start, with: replacement)
        return result
    }
}
