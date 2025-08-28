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
    
    private var columns: [GridItem] {
        let itemSize = fileManager.viewMode.gridItemSize
        return [
            GridItem(.adaptive(minimum: itemSize, maximum: itemSize + 20), spacing: 16)
        ]
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(fileManager.displayItems.indices, id: \.self) { index in
                        let item = fileManager.displayItems[index]
                        FileIconItemView(
                            item: item,
                            fileManager: fileManager,
                            isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList
                        )
                        // report frame for drag selection
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: IconItemFramePreferenceKey.self,
                                    value: [item.id: geo.frame(in: .global)]
                                )
                            }
                        )
                        // Add simultaneous gesture to each item for rectangular selection
                        .simultaneousGesture(
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
                                            print("[iconItemDrag] STARTED on item \(item.name) - start=\(value.startLocation)") 
                                        }
                                    } else {
                                        fileManager.dragCurrentPoint = value.location
                                        fileManager.dragUnionMode = commandHeld
                                    }
                                    
                                    // Update selection during drag
                                    updateSelection()
                                }
                                .onEnded { value in
                                    if fileManager.debugMarquee {
                                        print("[iconItemDrag] ENDED on item \(item.name)")
                                    }
                                    fileManager.isDragSelecting = false
                                    fileManager.dragOriginalSelection = []
                                    fileManager.dragUnionMode = false
                                }
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
                    FileThumbnailView(item: item, size: iconSize)
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

