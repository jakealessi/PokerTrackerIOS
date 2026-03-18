//
//  ImageAttachmentsSection.swift
//  PokerTrackerIOS
//

import SwiftUI
import PhotosUI

/// Reusable section for attaching images to a session via PhotosPicker
struct ImageAttachmentsSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var imageIds: [String]
    /// When true, removes image file from disk when user taps remove. Use false when editing (clean up on save instead).
    var deleteOnRemove: Bool = true
    var wrapInSection: Bool = true
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration = 0
    
    var body: some View {
        Group {
            if wrapInSection {
                Section("Photos") {
                    sectionContent
                }
            } else {
                sectionContent
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 10,
            matching: .images
        ) {
            Label("Add Photos", systemImage: "photo.on.rectangle.angled")
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            loadTask?.cancel()
            loadGeneration += 1
            let generation = loadGeneration
            loadTask = Task {
                await loadAndSaveImages(from: newItems, generation: generation)
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
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
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            imageIds.removeAll { $0 == imageId }
                            if deleteOnRemove {
                                SessionImageStore.delete(imageId: imageId)
                            }
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
    
    private func loadAndSaveImages(from items: [PhotosPickerItem], generation: Int) async {
        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                guard loadGeneration == generation else { return }
                isLoading = false
                selectedItems = []
                loadTask = nil
            }
        }

        for item in items {
            guard !Task.isCancelled else { return }
            if let transferred = try? await item.loadTransferable(type: ImageDataTransfer.self),
               let image = UIImage(data: transferred.data),
               let compressed = SessionImageStore.compressForStorage(image),
               let id = SessionImageStore.save(compressed) {
                if Task.isCancelled {
                    SessionImageStore.delete(imageId: id)
                    return
                }
                await MainActor.run {
                    imageIds.append(id)
                }
            }
        }
    }
}

/// Displays a session image by ID
struct SessionImageView: View {
    let imageId: String
    @State private var image: UIImage?
    @State private var didFinishLoading = false
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .overlay {
                        if didFinishLoading {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .onAppear { loadImage() }
    }
    
    private func loadImage() {
        guard image == nil, !didFinishLoading, !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [imageId] in
            let loaded = SessionImageStore.loadImage(imageId: imageId)
            DispatchQueue.main.async {
                image = loaded
                didFinishLoading = true
                isLoading = false
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
