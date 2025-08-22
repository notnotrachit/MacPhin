import SwiftUI

struct FileContextMenu: View {
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        Group {
            if !fileManager.selectedItems.isEmpty {
                Button("Open") {
                    for item in fileManager.selectedItems {
                        fileManager.openItem(item)
                    }
                }
                
                if fileManager.selectedItems.count == 1 {
                    Button("Show in Finder") {
                        if let item = fileManager.selectedItems.first {
                            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
                        }
                    }
                }
                
                Divider()
                
                Button("Copy") {
                    copySelectedItems()
                }
                
                Button("Move to Trash") {
                    moveSelectedItemsToTrash()
                }
                
                Divider()
                
                Button("Get Info") {
                    showInfoForSelectedItems()
                }
            }
            
            Button("New Folder") {
                createNewFolder()
            }
            
            Divider()
            
            Button("Refresh") {
                fileManager.refresh()
            }
            
            Menu("View") {
                Button("List") { fileManager.viewMode = .list }
                Button("Icons") { fileManager.viewMode = .icons }
                Button("Columns") { fileManager.viewMode = .columns }
                
                Divider()
                
                Button(fileManager.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    fileManager.showHiddenFiles.toggle()
                    fileManager.refresh()
                }
            }
            
            Menu("Sort By") {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: { fileManager.setSortOption(option) }) {
                        HStack {
                            Text(option.rawValue)
                            if fileManager.sortBy == option {
                                Image(systemName: fileManager.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func copySelectedItems() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let urls = fileManager.selectedItems.map { $0.url }
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
    }
    
    private func moveSelectedItemsToTrash() {
        for item in fileManager.selectedItems {
            do {
                try Foundation.FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            } catch {
                print("Error moving item to trash: \(error)")
            }
        }
        fileManager.selectedItems.removeAll()
        fileManager.refresh()
    }
    
    private func createNewFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = "New Folder"
        alert.accessoryView = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let folderName = textField.stringValue
            let newFolderURL = fileManager.currentURL.appendingPathComponent(folderName)
            
            do {
                try Foundation.FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
                fileManager.refresh()
            } catch {
                let errorAlert = NSAlert(error: error)
                errorAlert.runModal()
            }
        }
    }
    
    private func showInfoForSelectedItems() {
        for item in fileManager.selectedItems {
            NSWorkspace.shared.open(item.url)
        }
    }
}

