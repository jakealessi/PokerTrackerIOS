//
//  ImageAttachmentsSection.swift
//  PokerTrackerIOS
//

import SwiftUI
import PhotosUI

/// Reusable section for attaching images to a session via PhotosPicker
struct ImageAttachmentsSection: View {
    @Binding var imageIds: [String]
    /// When true, removes image file from disk when user taps remove. Use false when editing (clean up on save instead).
    var deleteOnRemove: Bool = true
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    
    var body: some View {
        Section("Photos") {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add Photos", systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await loadAndSaveImages(from: newItems)
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            
            if !imageIds.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80), spacing: 8)
                ], spacing: 8) {
                    ForEach(imageIds, id: \.self) { imageId in
                        ZStack(alignment: .topTrailing) {
                            SessionImageView(imageId: imageId)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(height: 80)
                                .clipped()
                                .cornerRadius(8)
                            
                            Button {
                                imageIds.removeAll { $0 == imageId }
                                if deleteOnRemove {
                                    SessionImageStore.delete(imageId: imageId)
                                }
                                HapticManager.lightTap()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1)
                            }
                            .padding(4)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func loadAndSaveImages(from items: [PhotosPickerItem]) async {
        isLoading = true
        selectedItems = []
        
        for item in items {
            if let transferred = try? await item.loadTransferable(type: ImageDataTransfer.self),
               let image = UIImage(data: transferred.data),
               let compressed = SessionImageStore.compressForStorage(image),
               let id = SessionImageStore.save(compressed) {
                await MainActor.run {
                    imageIds.append(id)
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
}

/// Displays a session image by ID
struct SessionImageView: View {
    let imageId: String
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .onAppear { loadImage() }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = SessionImageStore.loadImage(imageId: imageId)
            DispatchQueue.main.async {
                image = loaded
            }
        }
    }
}

/// Transferable wrapper for loading image Data from PhotosPickerItem
private struct ImageDataTransfer: Transferable {
    let data: Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { ImageDataTransfer(data: $0) }
    }
}
