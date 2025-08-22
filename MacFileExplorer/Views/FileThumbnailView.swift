import SwiftUI
import QuickLook
import AVFoundation

struct FileThumbnailView: View {
    let item: FileItem
    let size: CGSize
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .cornerRadius(4)
            } else if isLoading {
                ProgressView()
                    .frame(width: size.width, height: size.height)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: min(size.width, size.height) * 0.6))
                    .foregroundColor(item.iconColor)
                    .frame(width: size.width, height: size.height)
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: item.url) { _ in
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard !item.isDirectory else { return }
        
        let fileExtension = item.url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "wmv"]
        let documentExtensions = ["pdf", "doc", "docx", "txt", "rtf"]
        
        if imageExtensions.contains(fileExtension) {
            loadImageThumbnail()
        } else if videoExtensions.contains(fileExtension) {
            loadVideoThumbnail()
        } else if documentExtensions.contains(fileExtension) {
            loadDocumentThumbnail()
        }
    }
    
    private func loadImageThumbnail() {
        isLoading = true
        
        Task {
            let image = NSImage(contentsOf: item.url)
            await MainActor.run {
                self.thumbnail = image?.resized(to: size)
                self.isLoading = false
            }
        }
    }
    
    private func loadVideoThumbnail() {
        isLoading = true
        
        Task {
            do {
                let asset = AVAsset(url: item.url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                let time = CMTime(seconds: 1, preferredTimescale: 60)
                let cgImage = try await imageGenerator.image(at: time).image
                
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                
                await MainActor.run {
                    self.thumbnail = nsImage.resized(to: size)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadDocumentThumbnail() {
        isLoading = true
        
        Task {
            let thumbnailSize = CGSize(width: size.width * 2, height: size.height * 2) // Higher resolution
            
            if let thumbnail = await generateQuickLookThumbnail(for: item.url, size: thumbnailSize) {
                await MainActor.run {
                    self.thumbnail = thumbnail
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        // Simplified thumbnail generation without QuickLook
        if let image = NSImage(contentsOf: url) {
            return image.resized(to: size)
        }
        return nil
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