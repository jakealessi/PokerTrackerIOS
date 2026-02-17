//
//  VenueCleaner.swift
//  PokerTrackerIOS
//

import UIKit

enum VenueCleaner {
    /// Cleans parsed venue: trims, capitalizes, optionally spell-corrects
    static func clean(_ venue: String?) -> String? {
        let trimmed = venue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        var s = titleCase(trimmed)
        // Only spell-correct when input was all lowercase (likely a typo, not proper noun)
        if trimmed == trimmed.lowercased(), let corrected = spellCorrect(s), corrected != s {
            s = corrected
        }
        return s.isEmpty ? nil : s
    }
    
    private static func titleCase(_ s: String) -> String {
        s.lowercased()
            .split(separator: " ")
            .map { word in
                let str = String(word)
                guard let first = str.unicodeScalars.first else { return str }
                return str.replacingCharacters(in: str.startIndex..<str.index(after: str.startIndex), with: String(first).uppercased())
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
