//
//  SessionImageStore.swift
//  PokerTrackerIOS
//

import Foundation
import UIKit

/// Saves and loads session images to/from the app's Documents directory.
enum SessionImageStore {
    private static let subdirectory = "SessionImages"
    
    static var imagesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(subdirectory, isDirectory: true)
    }
    
    /// Save image data and return the assigned image ID (UUID string)
    static func save(_ imageData: Data) -> String? {
        let imageId = UUID().uuidString
        let url = imagesDirectory.appendingPathComponent("\(imageId).jpg")
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try imageData.write(to: url, options: .atomic)
            return imageId
        } catch {
            return nil
        }
    }
    
    /// Load image data for a given image ID
    static func load(imageId: String) -> Data? {
        let url = imagesDirectory.appendingPathComponent("\(imageId).jpg")
        return try? Data(contentsOf: url)
    }
    
    /// Load UIImage for a given image ID
    static func loadImage(imageId: String) -> UIImage? {
        guard let data = load(imageId: imageId) else { return nil }
        return UIImage(data: data)
    }
    
    /// Delete image by ID
    static func delete(imageId: String) {
        let url = imagesDirectory.appendingPathComponent("\(imageId).jpg")
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Delete multiple images by ID
    static func delete(imageIds: [String]) {
        for id in imageIds {
            delete(imageId: id)
        }
    }
    
    /// Compress image to JPEG for storage (max dimension 1200, quality 0.8)
    static func compressForStorage(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1200
        var scaled = image
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let ratio = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: size)
            scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}
