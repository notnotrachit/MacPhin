import SwiftUI

struct FileColumnView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var columnWidth: CGFloat = 200
    
    var body: some View {
        HSplitView {
            // Main file list
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
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 200)
            
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
                fileManager.selectItem(item)
            }
            .background(
                fileManager.selectedItems.contains(item) ? 
                Color.accentColor.opacity(0.3) : 
                isKeyboardSelected ? Color.accentColor.opacity(0.1) : Color.clear
            )
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

