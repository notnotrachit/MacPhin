import SwiftUI
import QuickLook
import AVFoundation
import Combine

// MARK: - Optimized Thumbnail Manager
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

// MARK: - Lazy Loading Grid View
struct LazyFileGridView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var visibleRange: Range<Int> = 0..<50
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private var columns: [GridItem] {
        let itemSize = fileManager.viewMode.gridItemSize
        return [
            GridItem(.adaptive(minimum: itemSize, maximum: itemSize + 20), spacing: 16)
        ]
    }
    
    private var visibleItems: [FileItem] {
        let items = fileManager.displayItems
        let endIndex = min(visibleRange.upperBound, items.count)
        let startIndex = min(visibleRange.lowerBound, endIndex)
        return Array(items[startIndex..<endIndex])
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            let globalIndex = visibleRange.lowerBound + index
                            LazyFileIconItemView(
                                item: item,
                                fileManager: fileManager,
                                isKeyboardSelected: fileManager.keyboardSelectedIndex == globalIndex && fileManager.focusedField == .fileList
                            )
                            .id(item.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: IconItemFramePreferenceKey.self,
                                        value: [item.id: geo.frame(in: .global)]
                                    )
                                }
                            )
                            .onAppear {
                                updateVisibleRange(for: globalIndex)
                            }
                        }
                    }
                    .padding()
                }
                .onPreferenceChange(IconItemFramePreferenceKey.self) { frames in
                    itemFrames = frames
                    updateSelection()
                }
            }
            
            // Marquee selection overlay
            if fileManager.isDragSelecting {
                MarqueeOverlay(fileManager: fileManager)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
    }
    
    private func updateVisibleRange(for index: Int) {
        let bufferSize = 25
        let newStart = max(0, index - bufferSize)
        let newEnd = min(fileManager.displayItems.count, index + bufferSize * 2)
        
        if newStart != visibleRange.lowerBound || newEnd != visibleRange.upperBound {
            visibleRange = newStart..<newEnd
        }
    }
    
    private func updateSelection() {
        guard fileManager.isDragSelecting else { return }
        
        var newlySelected: Set<FileItem> = fileManager.dragUnionMode ? fileManager.dragOriginalSelection : []
        let marqueeRect = CGRect(
            x: min(fileManager.dragStartPoint.x, fileManager.dragCurrentPoint.x),
            y: min(fileManager.dragStartPoint.y, fileManager.dragCurrentPoint.y),
            width: abs(fileManager.dragCurrentPoint.x - fileManager.dragStartPoint.x),
            height: abs(fileManager.dragCurrentPoint.y - fileManager.dragStartPoint.y)
        )
        
        for (id, frame) in itemFrames {
            if frame.intersects(marqueeRect) {
                if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                    newlySelected.insert(item)
                }
            }
        }
        
        fileManager.selectedItems = newlySelected
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let commandHeld = modifiers.contains(.command)
        
        if !fileManager.isDragSelecting {
            fileManager.isDragSelecting = true
            fileManager.dragStartPoint = value.startLocation
            fileManager.dragCurrentPoint = value.location
            fileManager.dragOriginalSelection = fileManager.selectedItems
            fileManager.dragUnionMode = commandHeld
        } else {
            fileManager.dragCurrentPoint = value.location
            fileManager.dragUnionMode = commandHeld
        }
        
        updateSelection()
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        fileManager.isDragSelecting = false
        fileManager.dragOriginalSelection = []
        fileManager.dragUnionMode = false
    }
}

struct LazyFileIconItemView: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    let isKeyboardSelected: Bool
    
    private var isSelected: Bool {
        fileManager.isItemSelected(item)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.3)
        } else if isKeyboardSelected {
            return Color.accentColor.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var iconSize: CGSize {
        fileManager.viewMode.iconSize
    }
    
    private var fontSize: Font {
        switch fileManager.viewMode {
        case .smallIcons: return .system(size: 24)
        case .mediumIcons: return .system(size: 48)
        case .largeIcons: return .system(size: 96)
        default: return .system(size: 48)
        }
    }
    
    private var textFont: Font {
        switch fileManager.viewMode {
        case .smallIcons: return .caption2
        case .mediumIcons: return .caption
        case .largeIcons: return .footnote
        default: return .caption
        }
    }
    
    private var frameWidth: CGFloat {
        fileManager.viewMode.gridItemSize - 20
    }
    
    var body: some View {
        DraggableFileView(item: item) {
            VStack(spacing: 8) {
                // Thumbnail or icon
                if item.isDirectory {
                    Image(systemName: item.icon)
                        .font(fontSize)
                        .foregroundColor(item.iconColor)
                        .frame(width: iconSize.width, height: iconSize.height)
                } else {
                    OptimizedThumbnailView(item: item, size: iconSize)
                }
                
                // File name
                Text(item.name)
                    .font(textFont)
                    .lineLimit(fileManager.viewMode == .largeIcons ? 3 : 2)
                    .multilineTextAlignment(.center)
                    .frame(width: frameWidth)
                    .truncationMode(.middle)
            }
            .padding(8)
            .background(backgroundColor)
            .overlay(
                isKeyboardSelected ? 
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2) : nil
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                fileManager.openItem(item)
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                        var eventModifiers: EventModifiers = []
                        if modifiers.contains(.command) { eventModifiers.insert(.command) }
                        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
                        if modifiers.contains(.option) { eventModifiers.insert(.option) }
                        if modifiers.contains(.control) { eventModifiers.insert(.control) }
                        
                        fileManager.selectItem(item, withModifiers: eventModifiers)
                    }
            )
        }
    }
}

struct MarqueeOverlay: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        GeometryReader { geometry in
            let globalToLocal = { (point: CGPoint) -> CGPoint in
                let frame = geometry.frame(in: .global)
                return CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            }
            
            let localStart = globalToLocal(fileManager.dragStartPoint)
            let localCurrent = globalToLocal(fileManager.dragCurrentPoint)
            
            let rect = CGRect(
                x: min(localStart.x, localCurrent.x),
                y: min(localStart.y, localCurrent.y),
                width: abs(localCurrent.x - localStart.x),
                height: abs(localCurrent.y - localStart.y)
            )
            
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1)
                .background(Color.accentColor.opacity(0.15))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }
}
