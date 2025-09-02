import SwiftUI

// Preference key to collect frames of icon items for drag selection
struct IconItemFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]

    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private let itemSize: CGFloat = 120
    private let spacing: CGFloat = 16
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 1)
    }
    
    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: itemSize, maximum: itemSize), spacing: spacing)]
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: adaptiveColumns, spacing: spacing) {
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

// MARK: - Lazy Loading Grid View
struct LazyFileGridView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var visibleRange: Range<Int> = 0..<50
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollPosition: CGPoint = .zero
    
    private var itemSize: CGFloat {
        fileManager.viewMode.gridItemSize
    }
    
    private var columns: [GridItem] {
        [
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
                                isKeyboardSelected: fileManager.keyboardSelectedIndex == globalIndex && fileManager.focusedField == .fileList,
                                fixedSize: itemSize
                            )
                            .id(item.id)
                            .frame(width: itemSize, height: itemSize + 40) // Fixed frame for consistent sizing
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
    let fixedSize: CGFloat
    
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
        let size = fixedSize * 0.6
        return CGSize(width: size, height: size)
    }
    
    private var fontSize: Font {
        let size = fixedSize * 0.3
        return .system(size: size)
    }
    
    private var textFont: Font {
        let size = fixedSize * 0.12
        return .system(size: size)
    }
    
    private var frameWidth: CGFloat {
        fixedSize - 16
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

struct SimplifiedIconItemView: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    let isKeyboardSelected: Bool
    let fixedSize: CGFloat
    let updateSelection: () -> Void
    
    var body: some View {
        LazyFileIconItemView(
            item: item,
            fileManager: fileManager,
            isKeyboardSelected: isKeyboardSelected,
            fixedSize: fixedSize
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: IconItemFramePreferenceKey.self,
                    value: [item.id: geo.frame(in: .global)]
                )
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
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

// Legacy FileIconView implementation kept for reference
struct LegacyFileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private func updateSelection() {
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
            print("[iconMarquee] Checking intersection - marqueeRect=\(marqueeRect) with \(itemFrames.count) frames")
        }

        for (id, frame) in itemFrames {
            let intersects = frame.intersects(marqueeRect)
            if fileManager.debugMarquee {
                print("[iconMarquee] Item id=\(id): frame=\(frame), intersects=\(intersects)")
            }
            if intersects {
                if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                    newlySelected.insert(item)
                    if fileManager.debugMarquee {
                        print("[iconMarquee] Added item: \(item.name)")
                    }
                } else if fileManager.debugMarquee {
                    print("[iconMarquee] Could not find item with id=\(id)")
                }
            }
        }
        if fileManager.debugMarquee {
            print("[iconMarquee] Final selection: \(newlySelected.map({ $0.name }))")
        }
        fileManager.selectedItems = newlySelected
    }
    
    private var itemSize: CGFloat {
        fileManager.viewMode.gridItemSize
    }
    
    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: itemSize, maximum: itemSize + 20), spacing: 16)
        ]
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(fileManager.displayItems.indices, id: \.self) { index in
                        let item = fileManager.displayItems[index]
                        SimplifiedIconItemView(
                            item: item,
                            fileManager: fileManager,
                            isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList,
                            fixedSize: itemSize,
                            updateSelection: updateSelection
                        )
                    }
                }
                .background(
                    // Background area for deselecting on empty space clicks
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    fileManager.deselectAll()
                                }
                        )
                )
                .padding()
            }
            .contextMenu {
                FileContextMenu(fileManager: fileManager)
            }
            
            // Marquee overlay for rectangular selection
            if fileManager.isDragSelecting {
                GeometryReader { geometry in
                    let globalToLocal = { (point: CGPoint) -> CGPoint in
                        // Convert global coordinates to local coordinates
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
        .onPreferenceChange(IconItemFramePreferenceKey.self) { frames in
            if fileManager.debugMarquee {
                print("[iconFrames] Received \(frames.count) frames: \(frames.mapValues { "\($0)" })")
            }
            
            // Store frames in local state
            itemFrames = frames
            
            // Update selection if currently dragging
            updateSelection()
        }
        // Background drag gesture for rectangular selection when starting on empty space
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
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
                            print("[iconBgDrag] STARTED - start=\(value.startLocation) current=\(value.location) cmd=\(commandHeld)") 
                        }
                    } else {
                        fileManager.dragCurrentPoint = value.location
                        fileManager.dragUnionMode = commandHeld
                        if fileManager.debugMarquee { 
                            print("[iconBgDrag] CONTINUE - current=\(value.location) cmd=\(commandHeld)") 
                        }
                    }
                    
                    // Update selection during drag
                    updateSelection()
                }
                .onEnded { value in
                    if fileManager.debugMarquee {
                        print("[iconBgDrag] ENDED at \(value.location)")
                    }
                    fileManager.isDragSelecting = false
                    fileManager.dragOriginalSelection = []
                    fileManager.dragUnionMode = false
                }
        )
    }
}

struct FileIconItemView: View {
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
        case .smallIcons:
            return .system(size: 24)
        case .mediumIcons:
            return .system(size: 48)
        case .largeIcons:
            return .system(size: 96)
        default:
            return .system(size: 48)
        }
    }
    
    private var textFont: Font {
        switch fileManager.viewMode {
        case .smallIcons:
            return .caption2
        case .mediumIcons:
            return .caption
        case .largeIcons:
            return .footnote
        default:
            return .caption
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
        }
    }
}

