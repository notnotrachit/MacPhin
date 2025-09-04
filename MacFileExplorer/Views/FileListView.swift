import SwiftUI

// Local preference key to collect frames of rows inside the list. Kept in this file to avoid
// any target membership / ordering issues during compile.
struct ItemFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]

    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FileListView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private let itemHeight: CGFloat = 20
    
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
        DraggableFileView(item: item) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
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

// MARK: - Optimized List View with Virtual Scrolling
struct OptimizedFileListView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var visibleRange: Range<Int> = 0..<100
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollOffset: CGFloat = 0
    
    private let itemHeight: CGFloat = 20
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
                                    isKeyboardSelected: fileManager.keyboardSelectedIndex == indexedItem.index && fileManager.focusedField == .fileList,
                                    rowIndex: indexedItem.index
                                )
                                .frame(height: itemHeight)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
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

// Legacy FileListView implementation kept for reference
struct LegacyFileListView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private func updateListSelection() {
        guard fileManager.isDragSelecting else { return }
        
        // Start with either the original selection (if union mode) or an empty set
        var newlySelected: Set<FileItem> = fileManager.dragUnionMode ? fileManager.dragOriginalSelection : []
        let marqueeRect = CGRect(
            x: min(fileManager.dragStartPoint.x, fileManager.dragCurrentPoint.x),
            y: min(fileManager.dragStartPoint.y, fileManager.dragCurrentPoint.y),
            width: abs(fileManager.dragCurrentPoint.x - fileManager.dragStartPoint.x),
            height: abs(fileManager.dragCurrentPoint.y - fileManager.dragStartPoint.y)
        )

        if fileManager.debugMarquee {
            print("[listMarquee] Checking intersection - marqueeRect=\(marqueeRect) with \(itemFrames.count) frames")
        }

        for (id, frame) in itemFrames {
            let intersects = frame.intersects(marqueeRect)
            if fileManager.debugMarquee {
                print("[listMarquee] Item id=\(id): frame=\(frame), intersects=\(intersects)")
            }
            if intersects {
                if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                    newlySelected.insert(item)
                    if fileManager.debugMarquee {
                        print("[listMarquee] Added item: \(item.name)")
                    }
                } else if fileManager.debugMarquee {
                    print("[listMarquee] Could not find item with id=\(id)")
                }
            }
        }
        if fileManager.debugMarquee {
            print("[listMarquee] Final selection: \(newlySelected.map({ $0.name }))")
        }
        fileManager.selectedItems = newlySelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            
            // File list with drag (Cmd+drag) marquee selection
            ZStack(alignment: .topLeading) {
                // Background for empty space clicks
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fileManager.deselectAll()
                    }
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(fileManager.displayItems.indices, id: \.self) { index in
                            let item = fileManager.displayItems[index]
                            FileListRowView(
                                item: item,
                                fileManager: fileManager,
                                isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList,
                                updateSelection: {
                                    updateListSelection()
                                }
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList ?
                                Color.accentColor.opacity(0.1) : Color.clear
                            )
                            // report frame for drag selection
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: ItemFramePreferenceKey.self, value: [item.id: geo.frame(in: .named("fileListSpace"))])
                            })
                        }
                        
                        // Add spacer to fill remaining space and make it tappable
                        Spacer()
                            .frame(minHeight: 100)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                fileManager.deselectAll()
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    fileManager.deselectAll()
                }
                .contextMenu {
                    FileContextMenu(fileManager: fileManager)
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
            .coordinateSpace(name: "fileListSpace")
            .clipped() // Prevent overflow beyond the view bounds
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                // Only update if frames actually changed to avoid excessive updates
                if itemFrames != frames {
                    itemFrames = frames
                    
                    // Update selection if currently dragging
                    if fileManager.isDragSelecting {
                        updateListSelection()
                    }
                }
            }
            // Background drag gesture for rectangular selection
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("fileListSpace"))
                .onChanged { value in
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    let commandHeld = modifiers.contains(.command)
                    
                    if !fileManager.isDragSelecting {
                        fileManager.isDragSelecting = true
                        fileManager.dragStartPoint = value.startLocation
                        fileManager.dragCurrentPoint = value.location
                        fileManager.dragOriginalSelection = fileManager.selectedItems
                        fileManager.dragUnionMode = commandHeld
                        if fileManager.debugMarquee { print("[listBgDrag] start=\(value.startLocation) current=\(value.location) cmd=\(commandHeld)") }
                    } else {
                        fileManager.dragCurrentPoint = value.location
                        // update union mode dynamically if modifier changed during drag
                        fileManager.dragUnionMode = commandHeld
                        if fileManager.debugMarquee { print("[listBgDrag] move current=\(value.location) cmd=\(commandHeld)") }
                    }
                    
                    // Update selection during drag
                    updateListSelection()
                }
                .onEnded { _ in
                    fileManager.isDragSelecting = false
                    fileManager.dragOriginalSelection = []
                    fileManager.dragUnionMode = false
                }
            )
        }
    }
}

struct FileListRowView: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    let isKeyboardSelected: Bool
    let updateSelection: () -> Void
    
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
                        // Immediate selection without waiting for gesture recognition
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

struct SelectableDraggableFileView: View {
    let item: FileItem
    let fileManager: FileExplorerManager
    let updateSelection: () -> Void
    let content: AnyView
    @State private var dragStartTime: Date?
    @State private var dragStartLocation: CGPoint = .zero
    
    init<Content: View>(item: FileItem, fileManager: FileExplorerManager, updateSelection: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.item = item
        self.fileManager = fileManager
        self.updateSelection = updateSelection
        self.content = AnyView(content())
    }
    
    var body: some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("fileListSpace"))
                    .onChanged { value in
                        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                        let commandHeld = modifiers.contains(.command)
                        
                        if !fileManager.isDragSelecting {
                            fileManager.isDragSelecting = true
                            fileManager.dragStartPoint = value.startLocation
                            fileManager.dragCurrentPoint = value.location
                            fileManager.dragOriginalSelection = fileManager.selectedItems
                            fileManager.dragUnionMode = commandHeld
                            if fileManager.debugMarquee { 
                                print("[listItemDrag] STARTED selection on item \(item.name)") 
                            }
                        } else {
                            fileManager.dragCurrentPoint = value.location
                            fileManager.dragUnionMode = commandHeld
                        }
                        
                        // Update selection during drag
                        updateSelection()
                    }
                    .onEnded { value in
                        if fileManager.isDragSelecting {
                            fileManager.isDragSelecting = false
                            fileManager.dragOriginalSelection = []
                            fileManager.dragUnionMode = false
                            if fileManager.debugMarquee {
                                print("[listItemDrag] ENDED selection on item \(item.name)")
                            }
                        }
                    }
            )
            .onDrag {
                // Only provide drag data if this is a file drag (not selection drag)
                if !fileManager.isDragSelecting {
                    return NSItemProvider(object: item.url as NSURL)
                } else {
                    return NSItemProvider()
                }
            }
    }
}

