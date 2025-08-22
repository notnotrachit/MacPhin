import SwiftUI

struct FileIconView: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(fileManager.items, id: \.id) { item in
                    FileIconItemView(item: item, fileManager: fileManager)
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
    
    var body: some View {
        VStack(spacing: 8) {
            // Large icon
            Image(systemName: item.icon)
                .font(.system(size: 48))
                .foregroundColor(item.iconColor)
                .frame(width: 64, height: 64)
            
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
            Color.accentColor.opacity(0.3) : Color.clear
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

