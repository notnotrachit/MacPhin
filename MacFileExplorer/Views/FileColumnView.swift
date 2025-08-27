import SwiftUI

// Preference key to collect frames of column items for drag selection
struct ColumnItemFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]

    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FileColumnView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var columnWidth: CGFloat = 200
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    var body: some View {
        HSplitView {
            // Main file list with rectangular selection
            ZStack(alignment: .topLeading) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(fileManager.displayItems.indices, id: \.self) { index in
                            let item = fileManager.displayItems[index]
                            FileColumnRowView(
                                item: item,
                                fileManager: fileManager,
                                isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList,
                                updateSelection: {
                                    updateColumnSelection()
                                }
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList ?
                                Color.accentColor.opacity(0.1) : Color.clear
                            )
                            // report frame for drag selection
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: ColumnItemFramePreferenceKey.self, value: [item.id: geo.frame(in: .named("columnViewSpace"))])
                            })
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 200)
                
                // Marquee overlay for rectangular selection
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
            .coordinateSpace(name: "columnViewSpace")
            .clipped() // Prevent overflow beyond the view bounds
            .onPreferenceChange(ColumnItemFramePreferenceKey.self) { frames in
                // Store frames for selection calculation
                itemFrames = frames
                
                // Update selection if currently dragging
                updateColumnSelection()
            }
            // Background drag gesture for rectangular selection - only on the LazyVStack, not the Spacer
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("columnViewSpace"))
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
                        if fileManager.debugMarquee { print("[columnBgDrag] start=\(value.startLocation) current=\(value.location) cmd=\(commandHeld)") }
                    } else {
                        fileManager.dragCurrentPoint = value.location
                        // update union mode dynamically if modifier changed during drag
                        fileManager.dragUnionMode = commandHeld
                        if fileManager.debugMarquee { print("[columnBgDrag] move current=\(value.location) cmd=\(commandHeld)") }
                    }
                    
                    // Update selection during drag
                    updateColumnSelection()
                }
                .onEnded { _ in
                    fileManager.isDragSelecting = false
                    fileManager.dragOriginalSelection = []
                    fileManager.dragUnionMode = false
                }
            )
            
            // Preview/Details panel
            if let selectedItem = fileManager.selectedItems.first {
                QuickPreviewView(item: selectedItem)
                    .frame(minWidth: 250, maxWidth: 400)
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a file to preview")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 250, maxWidth: 400)
            }
        }
        .contextMenu {
            FileContextMenu(fileManager: fileManager)
        }
    }
    
    private func updateColumnSelection() {
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
            print("[columnMarquee] Checking intersection - marqueeRect=\(marqueeRect) with \(itemFrames.count) frames")
        }

        for (id, frame) in itemFrames {
            let intersects = frame.intersects(marqueeRect)
            if fileManager.debugMarquee {
                print("[columnMarquee] Item id=\(id): frame=\(frame), intersects=\(intersects)")
            }
            if intersects {
                if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                    newlySelected.insert(item)
                    if fileManager.debugMarquee {
                        print("[columnMarquee] Added item: \(item.name)")
                    }
                } else if fileManager.debugMarquee {
                    print("[columnMarquee] Could not find item with id=\(id)")
                }
            }
        }
        if fileManager.debugMarquee {
            print("[columnMarquee] Final selection: \(newlySelected.map({ $0.name }))")
        }
        fileManager.selectedItems = newlySelected
    }
}

struct FileColumnRowView: View {
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
        SelectableDraggableFileView(item: item, fileManager: fileManager, updateSelection: updateSelection) {
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
                
                Spacer()
                
                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

struct FileDetailsView: View {
    let item: FileItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Large icon
            HStack {
                Spacer()
                Image(systemName: item.icon)
                    .font(.system(size: 64))
                    .foregroundColor(item.iconColor)
                Spacer()
            }
            
            // File name
            Text(item.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            Divider()
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Type", value: item.isDirectory ? "Folder" : item.url.pathExtension.uppercased())
                DetailRow(label: "Size", value: item.displaySize)
                DetailRow(label: "Created", value: DateFormatter.localizedString(from: item.dateCreated, dateStyle: .medium, timeStyle: .short))
                DetailRow(label: "Modified", value: DateFormatter.localizedString(from: item.dateModified, dateStyle: .medium, timeStyle: .short))
                DetailRow(label: "Location", value: item.url.deletingLastPathComponent().path)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .lineLimit(nil)
        }
    }
}

