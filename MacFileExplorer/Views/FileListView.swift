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
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
                // Store frames for selection calculation
                itemFrames = frames
                
                // Update selection if currently dragging
                updateListSelection()
            }
            // Background drag gesture for rectangular selection - only on the LazyVStack, not the Spacer
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("fileListSpace"))
                .onChanged { value in
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    let commandHeld = modifiers.contains(.command)
                    
                    // Only start drag selection if we're within the content area (not in empty space)
                    let maxContentY = itemFrames.values.map { $0.maxY }.max() ?? 0
                    let dragY = max(value.startLocation.y, value.location.y)
                    
                    if dragY > maxContentY + 20 { // Allow small buffer
                        return // Don't start selection in empty space
                    }
                    
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
                        FileThumbnailView(item: item, size: CGSize(width: 16, height: 16))
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

