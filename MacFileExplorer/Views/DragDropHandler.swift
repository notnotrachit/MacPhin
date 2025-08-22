import SwiftUI
import UniformTypeIdentifiers

struct DragDropHandler: ViewModifier {
    let fileManager: FileExplorerManager
    let onDrop: (([URL]) -> Bool)?
    
    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                _ = onDrop?(urls) ?? handleDefaultDrop(urls: urls)
            }
        }
        
        return true
    }
    
    private func handleDefaultDrop(urls: [URL]) -> Bool {
        // Default behavior: move/copy files to current directory
        for url in urls {
            do {
                let destinationURL = fileManager.currentURL.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Error copying file: \(error)")
            }
        }
        fileManager.refresh()
        return true
    }
}

extension View {
    func onFileDrop(fileManager: FileExplorerManager, onDrop: (([URL]) -> Bool)? = nil) -> some View {
        self.modifier(DragDropHandler(fileManager: fileManager, onDrop: onDrop))
    }
}

struct DraggableFileView: View {
    let item: FileItem
    let content: AnyView
    
    init<Content: View>(item: FileItem, @ViewBuilder content: () -> Content) {
        self.item = item
        self.content = AnyView(content())
    }
    
    var body: some View {
        content
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            }
    }
}