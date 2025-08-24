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
                List(fileManager.displayItems.indices, id: \.self) { index in
                    let item = fileManager.displayItems[index]
                    FileListRowView(
                        item: item,
                        fileManager: fileManager,
                        isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .background(
                        fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList ?
                        Color.accentColor.opacity(0.1) : Color.clear
                    )
                    // report frame for drag selection
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ItemFramePreferenceKey.self, value: [item.id: geo.frame(in: .named("fileListSpace"))])
                    })
                }
                .listStyle(.plain)
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
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                // When dragging, compute which items intersect marquee
                if fileManager.isDragSelecting {
                    // Start with either the original selection (if union mode) or an empty set
                    var newlySelected: Set<FileItem> = fileManager.dragUnionMode ? fileManager.dragOriginalSelection : []
                    let minRect = CGRect(
                        x: min(fileManager.dragStartPoint.x, fileManager.dragCurrentPoint.x),
                        y: min(fileManager.dragStartPoint.y, fileManager.dragCurrentPoint.y),
                        width: abs(fileManager.dragCurrentPoint.x - fileManager.dragStartPoint.x),
                        height: abs(fileManager.dragCurrentPoint.y - fileManager.dragStartPoint.y)
                    )

                    for (id, frame) in frames {
                        if fileManager.debugMarquee {
                            print("[marquee] frame for id=\(id): \(frame)")
                        }
                        if frame.intersects(minRect) {
                            if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                                newlySelected.insert(item)
                            }
                        }
                    }
                    if fileManager.debugMarquee {
                        print("[marquee] rect=\(minRect) selected=\(newlySelected.map({ $0.name }))")
                    }
                    fileManager.selectedItems = newlySelected
                }
            }
            // Background drag gesture for rectangular selection
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("fileListSpace"))
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
    
    private var isSelected: Bool {
        fileManager.selectedItems.contains(item)
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
            .onTapGesture {
                // Only handle single taps, not drags
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                var eventModifiers: EventModifiers = []
                if modifiers.contains(.command) { eventModifiers.insert(.command) }
                if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
                if modifiers.contains(.option) { eventModifiers.insert(.option) }
                if modifiers.contains(.control) { eventModifiers.insert(.control) }
                
                // Direct call for immediate update
                fileManager.selectItem(item, withModifiers: eventModifiers)
            }
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

