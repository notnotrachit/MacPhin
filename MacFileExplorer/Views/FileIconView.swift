import SwiftUI

struct FileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    private var columns: [GridItem] {
        let itemSize = fileManager.viewMode.gridItemSize
        return [
            GridItem(.adaptive(minimum: itemSize, maximum: itemSize + 20), spacing: 16)
        ]
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(fileManager.displayItems.indices, id: \.self) { index in
                    let item = fileManager.displayItems[index]
                    FileIconItemView(
                        item: item, 
                        fileManager: fileManager,
                        isKeyboardSelected: fileManager.keyboardSelectedIndex == index && fileManager.focusedField == .fileList
                    )
                }
            }
            .padding()
        }
        .contextMenu {
            FileContextMenu(fileManager: fileManager)
        }
    }
}

struct FileIconItemView: View {
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
            .onTapGesture {
                // Immediate selection for better responsiveness
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                var eventModifiers: EventModifiers = []
                if modifiers.contains(.command) { eventModifiers.insert(.command) }
                if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
                if modifiers.contains(.option) { eventModifiers.insert(.option) }
                if modifiers.contains(.control) { eventModifiers.insert(.control) }
                
                // Direct call for immediate update
                fileManager.selectItem(item, withModifiers: eventModifiers)
            }
        }
    }
}

