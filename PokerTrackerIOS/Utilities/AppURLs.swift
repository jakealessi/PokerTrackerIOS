//
//  AppURLs.swift
//  PokerTrackerIOS
//
//  Centralized URLs for privacy policy, support, and other external links.
//

import Foundation

enum AppURLs {
    static let baseURL = "https://jakealessi.github.io/PortfolioWebsite"

    private static func resolvedURL(_ primary: String, fallback: String) -> URL {
        URL(string: primary) ?? URL(string: fallback) ?? URL(fileURLWithPath: "/")
    }
    
    static var privacyPolicy: URL {
        resolvedURL("\(baseURL)/privacy-policy", fallback: "https://jakealessi.github.io/PortfolioWebsite/privacy-policy")
    }
    
    static var support: URL {
        resolvedURL("\(baseURL)/support", fallback: "https://jakealessi.github.io/PortfolioWebsite/support")
    }

    /// Apple's standard EULA — use this or a custom terms URL
    static var termsOfUse: URL {
        resolvedURL(
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
            fallback: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
    }
}
