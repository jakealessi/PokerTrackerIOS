//
//  AppURLs.swift
//  PokerTrackerIOS
//
//  Centralized URLs for privacy policy, support, and other external links.
//

import Foundation

enum AppURLs {
    static let baseURL = "https://jakealessi.github.io/PortfolioWebsite"
    
    static var privacyPolicy: URL {
        URL(string: "\(baseURL)/privacy-policy")!
    }
    
    static var support: URL {
        URL(string: "\(baseURL)/support")!
    }

    /// Apple's standard EULA — use this or a custom terms URL
    static var termsOfUse: URL {
        URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }
}
