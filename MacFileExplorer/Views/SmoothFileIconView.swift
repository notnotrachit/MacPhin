import SwiftUI

// MARK: - Smooth Scrolling File Icon View
struct SmoothFileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private let itemSize: CGFloat = 120
    private let spacing: CGFloat = 16
    
    private var columns: [GridItem] {
        [GridItem(.fixed(itemSize), spacing: spacing)]
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(fileManager.displayItems.indices, id: \.self) { index in
                        let item = fileManager.displayItems[index]
                        SmoothFileIconItemView(
                            item: item,
                            fileManager: fileManager,
                            isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList
                        )
                        .frame(width: itemSize, height: itemSize + 30)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: IconItemFramePreferenceKey.self,
                                    value: [item.id: geo.frame(in: .global)]
                                )
                            }
                        )
                    }
                }
                .padding()
            }
            .onPreferenceChange(IconItemFramePreferenceKey.self) { frames in
                itemFrames = frames
                updateSelection()
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

struct SmoothFileIconItemView: View {
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
    
    var body: some View {
        DraggableFileView(item: item) {
            VStack(spacing: 4) {
                // Thumbnail or icon - fixed size
                if item.isDirectory {
                    Image(systemName: item.icon)
                        .font(.system(size: 48))
                        .foregroundColor(item.iconColor)
                        .frame(width: 80, height: 80)
                } else {
                    FastThumbnailView(item: item)
                        .frame(width: 80, height: 80)
                }
                
                // File name - fixed height
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100, height: 26)
                    .truncationMode(.middle)
            }
            .padding(4)
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

// MARK: - Fast Thumbnail View (No Animation, Fixed Size)
struct FastThumbnailView: View {
    let item: FileItem
    @State private var thumbnail: NSImage?
    @State private var hasLoaded = false
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 32))
                    .foregroundColor(item.iconColor)
            }
        }
        .onAppear {
            if !hasLoaded {
                loadThumbnail()
                hasLoaded = true
            }
        }
    }
    
    private func loadThumbnail() {
        let fileExtension = item.url.pathExtension.lowercased()
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        
        guard supportedExtensions.contains(fileExtension) else { return }
        
        Task {
            if let cachedThumbnail = ThumbnailManager.shared.getThumbnail(for: item.url, size: CGSize(width: 80, height: 80)) {
                await MainActor.run {
                    self.thumbnail = cachedThumbnail
                }
                return
            }
            
            let loadedThumbnail = await ThumbnailManager.shared.loadThumbnail(for: item.url, size: CGSize(width: 80, height: 80))
            
            await MainActor.run {
                self.thumbnail = loadedThumbnail
            }
        }
    }
}
