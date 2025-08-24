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
    
    var body: some View {
        HSplitView {
            // Main file list with rectangular selection
            ZStack(alignment: .topLeading) {
                VStack {
                    List(fileManager.displayItems.indices, id: \.self) { index in
                        let item = fileManager.displayItems[index]
                        FileColumnRowView(
                            item: item, 
                            fileManager: fileManager,
                            isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .background(
                            fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList ?
                            Color.accentColor.opacity(0.1) : Color.clear
                        )
                        // Report frame for drag selection
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ColumnItemFramePreferenceKey.self, value: [item.id: geo.frame(in: .named("columnViewSpace"))])
                        })
                    }
                    .listStyle(.plain)
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
            .onPreferenceChange(ColumnItemFramePreferenceKey.self) { frames in
                // When dragging, compute which items intersect marquee
                if fileManager.isDragSelecting {
                    // Start with either the original selection (if union mode) or an empty set
                    var newlySelected: Set<FileItem> = fileManager.dragUnionMode ? fileManager.dragOriginalSelection : []
                    let marqueeRect = CGRect(
                        x: min(fileManager.dragStartPoint.x, fileManager.dragCurrentPoint.x),
                        y: min(fileManager.dragStartPoint.y, fileManager.dragCurrentPoint.y),
                        width: abs(fileManager.dragCurrentPoint.x - fileManager.dragStartPoint.x),
                        height: abs(fileManager.dragCurrentPoint.y - fileManager.dragStartPoint.y)
                    )

                    for (id, frame) in frames {
                        if fileManager.debugMarquee {
                            print("[columnMarquee] frame for id=\(id): \(frame)")
                        }
                        if frame.intersects(marqueeRect) {
                            if let item = fileManager.displayItems.first(where: { $0.id == id }) {
                                newlySelected.insert(item)
                            }
                        }
                    }
                    if fileManager.debugMarquee {
                        print("[columnMarquee] rect=\(marqueeRect) selected=\(newlySelected.map({ $0.name }))")
                    }
                    fileManager.selectedItems = newlySelected
                }
            }
            // Background drag gesture for rectangular selection when starting on empty space
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("columnViewSpace"))
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
                                print("[columnBgDrag] start=\(value.startLocation) current=\(value.location) cmd=\(commandHeld)") 
                            }
                        } else {
                            fileManager.dragCurrentPoint = value.location
                            fileManager.dragUnionMode = commandHeld
                            if fileManager.debugMarquee { 
                                print("[columnBgDrag] move current=\(value.location) cmd=\(commandHeld)") 
                            }
                        }
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
}

struct FileColumnRowView: View {
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
            .onTapGesture {
                // Single tap selection
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                var eventModifiers: EventModifiers = []
                if modifiers.contains(.command) { eventModifiers.insert(.command) }
                if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
                if modifiers.contains(.option) { eventModifiers.insert(.option) }
                if modifiers.contains(.control) { eventModifiers.insert(.control) }
                
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

