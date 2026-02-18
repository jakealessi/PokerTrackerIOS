//
//  ActivitySheet.swift
//  PokerTrackerIOS
//

import SwiftUI
import UIKit

/// Presents the system share sheet (UIActivityViewController) to share multiple items (text, images, etc.)
struct ActivitySheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
