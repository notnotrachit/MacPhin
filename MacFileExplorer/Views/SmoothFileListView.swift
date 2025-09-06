import SwiftUI

// MARK: - Smooth Scrolling File List View
struct SmoothFileListView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private let itemHeight: CGFloat = 28
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ListHeaderView(fileManager: fileManager)
            
            // File list with fixed item heights
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fileManager.deselectAll()
                    }
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(fileManager.displayItems.indices, id: \.self) { index in
                            let item = fileManager.displayItems[index]
                            SmoothFileListRowView(
                                item: item,
                                fileManager: fileManager,
                                isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList,
                                rowIndex: index
                            )
                            .frame(height: itemHeight)
                            .background(
                                fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList ?
                                Color.accentColor.opacity(0.1) : Color.clear
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ItemFramePreferenceKey.self,
                                        value: [item.id: geo.frame(in: .named("fileListSpace"))]
                                    )
                                }
                            )
                        }
                    }
                }
                .coordinateSpace(name: "fileListSpace")
                .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                    itemFrames = frames
                    if fileManager.isDragSelecting {
                        updateSelection()
                    }
                }
                
                // Marquee overlay
                if fileManager.isDragSelecting {
                    let rect = CGRect(
                        x: min(fileManager.dragStartPoint.x, fileManager.dragCurrentPoint.x),
                        y: min(fileManager.dragStartPoint.y, fileManager.dragCurrentPoint.y),
                        width: abs(fileManager.dragCurrentPoint.x - fileManager.dragStartPoint.x),
                        height: abs(fileManager.dragCurrentPoint.y - fileManager.dragStartPoint.y)
                    )
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("fileListSpace"))
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
            .contextMenu {
                FileContextMenu(fileManager: fileManager)
            }
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
            // Check if drag starts on a selected item
            let dragStartPoint = value.startLocation
            var dragStartsOnSelectedItem = false
            
            for (id, frame) in itemFrames {
                if frame.contains(dragStartPoint) {
                    if let item = fileManager.displayItems.first(where: { $0.id == id }),
                       fileManager.isItemSelected(item) {
                        dragStartsOnSelectedItem = true
                        break
                    }
                }
            }
            
            // Only start marquee selection if not dragging a selected item
            if !dragStartsOnSelectedItem {
                fileManager.isDragSelecting = true
                fileManager.dragStartPoint = value.startLocation
                fileManager.dragCurrentPoint = value.location
                fileManager.dragOriginalSelection = fileManager.selectedItems
                fileManager.dragUnionMode = commandHeld
            }
        } else {
            fileManager.dragCurrentPoint = value.location
            fileManager.dragUnionMode = commandHeld
        }
        
        if fileManager.isDragSelecting {
            updateSelection()
        }
    }
    
    private func handleDragEnded() {
        fileManager.isDragSelecting = false
        fileManager.dragOriginalSelection = []
        fileManager.dragUnionMode = false
    }
}

struct SmoothFileListRowView: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    let isKeyboardSelected: Bool
    let rowIndex: Int
    
    private var isSelected: Bool {
        fileManager.isItemSelected(item)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.3)
        } else if isKeyboardSelected {
            return Color.accentColor.opacity(0.1)
        } else {
            // Alternating row colors
            return rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlAlternatingRowBackgroundColors[1])
        }
    }
    
    var body: some View {
        DraggableFileView(item: item, fileManager: fileManager) {
            HStack {
                // Icon/thumbnail and name
                HStack(spacing: 8) {
                    if item.isDirectory {
                        Image(systemName: item.icon)
                            .foregroundColor(item.iconColor)
                            .frame(width: 16, height: 16)
                    } else {
                        FastListThumbnailView(item: item)
                            .frame(width: 16, height: 16)
                    }
                    
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Date modified
                Text(item.dateModified, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
                
                // Type
                Text(item.isDirectory ? "Folder" : item.url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                
                // Size
                Text(item.displaySize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 8)
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
            .background(backgroundColor)
            .overlay(
                isKeyboardSelected ? 
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2) : nil
            )
            .cornerRadius(4)
        }
    }
}

// MARK: - Fast List Thumbnail View (Minimal, No Animation)
struct FastListThumbnailView: View {
    let item: FileItem
    @State private var thumbnail: NSImage?
    @State private var hasLoaded = false
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 12))
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
            if let cachedThumbnail = ThumbnailManager.shared.getThumbnail(for: item.url, size: CGSize(width: 16, height: 16)) {
                await MainActor.run {
                    self.thumbnail = cachedThumbnail
                }
                return
            }
            
            let loadedThumbnail = await ThumbnailManager.shared.loadThumbnail(for: item.url, size: CGSize(width: 16, height: 16))
            
            await MainActor.run {
                self.thumbnail = loadedThumbnail
            }
        }
    }
}
