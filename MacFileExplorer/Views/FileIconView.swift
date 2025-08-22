import SwiftUI

struct FileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
    ]
    
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
    
    var body: some View {
        DraggableFileView(item: item) {
            VStack(spacing: 8) {
                // Thumbnail or icon
                if item.isDirectory {
                    Image(systemName: item.icon)
                        .font(.system(size: 48))
                        .foregroundColor(item.iconColor)
                        .frame(width: 64, height: 64)
                } else {
                    FileThumbnailView(item: item, size: CGSize(width: 64, height: 64))
                }
                
                // File name
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .truncationMode(.middle)
            }
            .padding(8)
            .background(
                fileManager.selectedItems.contains(item) ? 
                Color.accentColor.opacity(0.3) : 
                isKeyboardSelected ? Color.accentColor.opacity(0.1) : Color.clear
            )
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
                fileManager.selectItem(item)
            }
        }
    }
}

