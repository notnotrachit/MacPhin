import SwiftUI
import QuickLook
import AVFoundation
import Combine

// MARK: - Thumbnail Manager
@MainActor
class ThumbnailManager: ObservableObject {
    static let shared = ThumbnailManager()
    
    private var cache: [String: NSImage] = [:]
    private var loadingTasks: [String: Task<NSImage?, Never>] = [:]
    private let maxCacheSize = 500
    private let thumbnailQueue = DispatchQueue(label: "thumbnailQueue", qos: .userInitiated, attributes: .concurrent)
    
    // Track cache access order for LRU eviction
    private var accessOrder: [String] = []
    
    private init() {}
    
    func getThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let key = cacheKey(for: url, size: size)
        
        // Update access order for LRU
        if let image = cache[key] {
            updateAccessOrder(for: key)
            return image
        }
        
        return nil
    }
    
    func loadThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = cacheKey(for: url, size: size)
        
        // Check cache first
        if let cached = cache[key] {
            updateAccessOrder(for: key)
            return cached
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[key] {
            return await existingTask.value
        }
        
        // Create new loading task
        let task = Task<NSImage?, Never> {
            let thumbnail = await generateThumbnail(for: url, size: size)
            
            await MainActor.run {
                self.loadingTasks.removeValue(forKey: key)
                if let thumbnail = thumbnail {
                    self.cacheThumbnail(thumbnail, for: key)
                }
            }
            
            return thumbnail
        }
        
        loadingTasks[key] = task
        return await task.value
    }
    
    private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                let fileExtension = url.pathExtension.lowercased()
                let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
                let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "wmv"]
                
                var thumbnail: NSImage?
                
                if imageExtensions.contains(fileExtension) {
                    thumbnail = self.generateImageThumbnail(for: url, size: size)
                } else if videoExtensions.contains(fileExtension) {
                    thumbnail = self.generateVideoThumbnail(for: url, size: size)
                } else {
                    thumbnail = self.generateDocumentThumbnail(for: url, size: size)
                }
                
                continuation.resume(returning: thumbnail)
            }
        }
    }
    
    private func generateImageThumbnail(for url: URL, size: CGSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2 // Retina support
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: size)
    }
    
    private func generateVideoThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        
        do {
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            return nil
        }
    }
    
    private func generateDocumentThumbnail(for url: URL, size: CGSize) -> NSImage? {
        // For now, return nil to use system icons
        // Could implement QuickLook thumbnail generation here
        return nil
    }
    
    private func cacheThumbnail(_ image: NSImage, for key: String) {
        // Evict old entries if cache is full
        if cache.count >= maxCacheSize {
            evictLRUEntries()
        }
        
        cache[key] = image
        updateAccessOrder(for: key)
    }
    
    private func updateAccessOrder(for key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func evictLRUEntries() {
        let entriesToRemove = cache.count - maxCacheSize + 50 // Remove 50 extra to avoid frequent evictions
        for i in 0..<min(entriesToRemove, accessOrder.count) {
            let keyToRemove = accessOrder[i]
            cache.removeValue(forKey: keyToRemove)
        }
        accessOrder.removeFirst(min(entriesToRemove, accessOrder.count))
    }
    
    private func cacheKey(for url: URL, size: CGSize) -> String {
        return "\(url.path)_\(Int(size.width))x\(Int(size.height))"
    }
    
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }
    
    func cancelLoading(for url: URL, size: CGSize) {
        let key = cacheKey(for: url, size: size)
        loadingTasks[key]?.cancel()
        loadingTasks.removeValue(forKey: key)
    }
}

// MARK: - Optimized Thumbnail View
struct OptimizedThumbnailView: View {
    let item: FileItem
    let size: CGSize
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    @StateObject private var thumbnailManager = ThumbnailManager.shared
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .cornerRadius(4)
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: size.width, height: size.height)
                    
                    ProgressView()
                        .scaleEffect(0.5)
                }
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: min(size.width, size.height) * 0.6))
                    .foregroundColor(item.iconColor)
                    .frame(width: size.width, height: size.height)
            }
        }
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onChange(of: item.url) { _ in
            loadThumbnailIfNeeded()
        }
        .onDisappear {
            // Cancel loading when view disappears
            thumbnailManager.cancelLoading(for: item.url, size: size)
        }
    }
    
    private func loadThumbnailIfNeeded() {
        guard !item.isDirectory else { return }
        
        // Check cache first
        if let cachedThumbnail = thumbnailManager.getThumbnail(for: item.url, size: size) {
            thumbnail = cachedThumbnail
            return
        }
        
        let fileExtension = item.url.pathExtension.lowercased()
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "mp4", "mov", "avi", "mkv", "m4v", "wmv"]
        
        guard supportedExtensions.contains(fileExtension) else { return }
        
        isLoading = true
        
        Task {
            let loadedThumbnail = await thumbnailManager.loadThumbnail(for: item.url, size: size)
            
            await MainActor.run {
                self.thumbnail = loadedThumbnail
                self.isLoading = false
            }
        }
    }
}

// Legacy FileThumbnailView - now redirects to OptimizedThumbnailView
struct FileThumbnailView: View {
    let item: FileItem
    let size: CGSize
    
    var body: some View {
        OptimizedThumbnailView(item: item, size: size)
    }
}

extension NSImage {
    func resized(to newSize: CGSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        let imageRect = NSRect(origin: .zero, size: newSize)
        let sourceRect = NSRect(origin: .zero, size: self.size)
        
        self.draw(in: imageRect, from: sourceRect, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}