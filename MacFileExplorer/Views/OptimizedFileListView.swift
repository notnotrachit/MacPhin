import SwiftUI

// MARK: - Optimized List View with Virtual Scrolling
struct OptimizedFileListView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var visibleRange: Range<Int> = 0..<100
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollOffset: CGFloat = 0
    
    private let itemHeight: CGFloat = 24
    private let bufferSize = 50
    
    private var visibleItems: [(index: Int, item: FileItem)] {
        let items = fileManager.displayItems
        let endIndex = min(visibleRange.upperBound, items.count)
        let startIndex = min(visibleRange.lowerBound, endIndex)
        return Array(items[startIndex..<endIndex].enumerated().map { (startIndex + $0.offset, $0.element) })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ListHeaderView(fileManager: fileManager)
            
            // Optimized file list
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fileManager.deselectAll()
                    }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Top spacer for items before visible range
                            if visibleRange.lowerBound > 0 {
                                Spacer()
                                    .frame(height: CGFloat(visibleRange.lowerBound) * itemHeight)
                            }
                            
                            // Visible items
                            ForEach(visibleItems, id: \.item.id) { indexedItem in
                                OptimizedFileListRowView(
                                    item: indexedItem.item,
                                    fileManager: fileManager,
                                    isKeyboardSelected: fileManager.keyboardSelectedIndex == indexedItem.index && fileManager.focusedField == .fileList
                                )
                                .frame(height: itemHeight)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    fileManager.keyboardSelectedIndex == indexedItem.index && fileManager.focusedField == .fileList ?
                                    Color.accentColor.opacity(0.1) : Color.clear
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ItemFramePreferenceKey.self,
                                            value: [indexedItem.item.id: geo.frame(in: .named("fileListSpace"))]
                                        )
                                    }
                                )
                                .onAppear {
                                    updateVisibleRange(for: indexedItem.index)
                                }
                                .id(indexedItem.item.id)
                            }
                            
                            // Bottom spacer for items after visible range
                            let remainingItems = fileManager.displayItems.count - visibleRange.upperBound
                            if remainingItems > 0 {
                                Spacer()
                                    .frame(height: CGFloat(remainingItems) * itemHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "fileListSpace")
                    .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                        if itemFrames != frames {
                            itemFrames = frames
                            if fileManager.isDragSelecting {
                                updateSelection()
                            }
                        }
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
    
    private func updateVisibleRange(for index: Int) {
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
    
    private func handleDragEnded() {
        fileManager.isDragSelecting = false
        fileManager.dragOriginalSelection = []
        fileManager.dragUnionMode = false
    }
}

struct ListHeaderView: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        HStack {
            Button(action: { fileManager.setSortOption(.name) }) {
                HStack {
                    Text("Name")
                    if fileManager.sortBy == .name {
                        Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: { fileManager.setSortOption(.dateModified) }) {
                HStack {
                    Text("Date Modified")
                    if fileManager.sortBy == .dateModified {
                        Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 150, alignment: .leading)
            
            Button(action: { fileManager.setSortOption(.type) }) {
                HStack {
                    Text("Type")
                    if fileManager.sortBy == .type {
                        Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 100, alignment: .leading)
            
            Button(action: { fileManager.setSortOption(.size) }) {
                HStack {
                    Text("Size")
                    if fileManager.sortBy == .size {
                        Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
}

struct OptimizedFileListRowView: View {
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
            HStack {
                // Icon/thumbnail and name
                HStack(spacing: 8) {
                    if item.isDirectory {
                        Image(systemName: item.icon)
                            .foregroundColor(item.iconColor)
                            .frame(width: 16, height: 16)
                    } else {
                        OptimizedThumbnailView(item: item, size: CGSize(width: 16, height: 16))
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
