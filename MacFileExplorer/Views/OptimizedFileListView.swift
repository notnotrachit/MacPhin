import SwiftUI

// MARK: - Resizable List Header Components

struct ResizableListHeaderView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var draggedColumn: String? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            // Name column
            ResizableColumnHeader(
                title: "Name",
                sortOption: .name,
                fileManager: fileManager,
                columnKey: "name",
                width: fileManager.getColumnWidth("name"),
                isFlexible: false
            )
            
            // Date Modified column
            ResizableColumnHeader(
                title: "Date Modified",
                sortOption: .dateModified,
                fileManager: fileManager,
                columnKey: "dateModified",
                width: fileManager.getColumnWidth("dateModified")
            )
            
            // Type column
            ResizableColumnHeader(
                title: "Type",
                sortOption: .type,
                fileManager: fileManager,
                columnKey: "type",
                width: fileManager.getColumnWidth("type")
            )
            
            // Size column
            ResizableColumnHeader(
                title: "Size",
                sortOption: .size,
                fileManager: fileManager,
                columnKey: "size",
                width: fileManager.getColumnWidth("size"),
                alignment: .trailing
            )
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
}

struct ResizableColumnHeader: View {
    let title: String
    let sortOption: SortOption
    @ObservedObject var fileManager: FileExplorerManager
    let columnKey: String
    let width: CGFloat
    let isFlexible: Bool
    let alignment: Alignment
    
    init(title: String, sortOption: SortOption, fileManager: FileExplorerManager, columnKey: String, width: CGFloat, isFlexible: Bool = false, alignment: Alignment = .leading) {
        self.title = title
        self.sortOption = sortOption
        self.fileManager = fileManager
        self.columnKey = columnKey
        self.width = width
        self.isFlexible = isFlexible
        self.alignment = alignment
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Column content
            Button(action: { fileManager.setSortOption(sortOption) }) {
                HStack {
                    Text(title)
                    if fileManager.sortBy == sortOption {
                        Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
            }
            .buttonStyle(.plain)
            .frame(width: fileManager.getColumnWidth(columnKey), alignment: alignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            // Resize handle (except for the last column)
            if columnKey != "size" {
                ResizeHandle(
                    columnKey: columnKey,
                    fileManager: fileManager
                )
            }
        }
    }
}

struct ResizeHandle: View {
    let columnKey: String
    @ObservedObject var fileManager: FileExplorerManager
    
    @State private var isHovering = false
    @State private var initialWidth: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill((isHovering || isDragging) ? Color.accentColor.opacity(0.15) : Color.clear)
            .frame(width: 16, height: 24)
            .overlay(
                Rectangle()
                    .fill((isHovering || isDragging) ? Color.accentColor.opacity(0.7) : Color.clear)
                    .frame(width: 2)
            )
            .contentShape(Rectangle())
            .clipped()
            .onHover { hovering in
                isHovering = hovering
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    NSCursor.resizeLeftRight.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            initialWidth = fileManager.getColumnWidth(columnKey)
                        }
                        let newWidth = max(50, min(500, initialWidth + value.translation.width))
                        fileManager.setColumnWidth(columnKey, width: newWidth)
                    }
                    .onEnded { value in
                        isDragging = false
                        initialWidth = 0
                    }
            )
    }
}


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
            ResizableListHeaderView(fileManager: fileManager)
            
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
                                    isKeyboardSelected: fileManager.keyboardSelectedIndex == indexedItem.index && fileManager.focusedField == .fileList,
                                    rowIndex: indexedItem.index
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
            HStack(spacing: 0) {
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
                .frame(width: fileManager.getColumnWidth("name"), alignment: .leading)
                .padding(.horizontal, 8)
                
                // Date modified
                Text(item.dateModified, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: fileManager.getColumnWidth("dateModified"), alignment: .leading)
                    .padding(.horizontal, 8)
                
                // Type
                Text(item.isDirectory ? "Folder" : item.url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: fileManager.getColumnWidth("type"), alignment: .leading)
                    .padding(.horizontal, 8)
                
                // Size
                Text(item.displaySize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: fileManager.getColumnWidth("size"), alignment: .trailing)
                    .padding(.horizontal, 8)
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
