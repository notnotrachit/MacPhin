import SwiftUI

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
            
            // File list
            List(fileManager.displayItems, id: \.id, selection: Binding(
                get: { fileManager.selectedItems },
                set: { fileManager.selectedItems = $0 }
            )) { item in
                FileListRowView(item: item, fileManager: fileManager)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .listStyle(.plain)
            .contextMenu {
                FileContextMenu(fileManager: fileManager)
            }
        }
    }
}

struct FileListRowView: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    
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
                fileManager.selectItem(item)
            }
            .background(
                fileManager.selectedItems.contains(item) ? 
                Color.accentColor.opacity(0.3) : Color.clear
            )
            .cornerRadius(4)
        }
    }
}

