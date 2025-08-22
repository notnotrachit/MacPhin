import Foundation
import AppKit

enum ClipboardOperation {
    case copy
    case cut
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var clipboardItems: [FileItem] = []
    @Published var operation: ClipboardOperation = .copy
    
    private init() {}
    
    func copyItems(_ items: [FileItem]) {
        clipboardItems = items
        operation = .copy
        
        // Also copy to system pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls = items.map { $0.url }
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
        
        print("Copied \(items.count) items to clipboard")
    }
    
    func cutItems(_ items: [FileItem]) {
        clipboardItems = items
        operation = .cut
        
        // Also copy to system pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls = items.map { $0.url }
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
        
        print("Cut \(items.count) items to clipboard")
    }
    
    func pasteItems(to destinationURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !clipboardItems.isEmpty else {
            completion(.failure(ClipboardError.noItemsInClipboard))
            return
        }
        
        Task {
            do {
                let fileManager = FileManager.default
                
                for item in clipboardItems {
                    let destinationPath = destinationURL.appendingPathComponent(item.name)
                    
                    switch operation {
                    case .copy:
                        try fileManager.copyItem(at: item.url, to: destinationPath)
                    case .cut:
                        try fileManager.moveItem(at: item.url, to: destinationPath)
                    }
                }
                
                // Clear clipboard after cut operation
                if operation == .cut {
                    await MainActor.run {
                        clipboardItems.removeAll()
                    }
                }
                
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func clearClipboard() {
        clipboardItems.removeAll()
    }
    
    var hasItems: Bool {
        !clipboardItems.isEmpty
    }
    
    var canPaste: Bool {
        hasItems
    }
}

enum ClipboardError: LocalizedError {
    case noItemsInClipboard
    case operationFailed
    
    var errorDescription: String? {
        switch self {
        case .noItemsInClipboard:
            return "No items in clipboard"
        case .operationFailed:
            return "Clipboard operation failed"
        }
    }
}