import Foundation
import SwiftUI

class FileExplorerManager: ObservableObject {
    @Published var currentURL: URL
    @Published var items: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var viewMode: ViewMode = .list
    @Published var sortBy: SortOption = .name
    @Published var sortAscending = true
    @Published var showHiddenFiles = false
    @Published var selectedItems: Set<FileItem> = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchResults: [FileItem] = []
    @Published var isInSearchMode = false
    @Published var searchScope: SearchScope = .currentFolder
    
    private var navigationHistory: [URL] = []
    private var currentHistoryIndex = -1
    private let fileManager = Foundation.FileManager.default
    
    var canGoBack: Bool {
        currentHistoryIndex > 0
    }
    
    var canGoForward: Bool {
        currentHistoryIndex < navigationHistory.count - 1
    }
    
    var canGoUp: Bool {
        currentURL.path != "/"
    }
    
    init() {
        self.currentURL = fileManager.homeDirectoryForCurrentUser
        loadItems()
    }
    
    
    func navigateTo(_ url: URL) {
        // Add to history if we're not navigating through history
        if currentHistoryIndex == navigationHistory.count - 1 {
            navigationHistory.append(url)
            currentHistoryIndex += 1
        } else {
            // Remove forward history and add new URL
            navigationHistory = Array(navigationHistory[0...currentHistoryIndex])
            navigationHistory.append(url)
            currentHistoryIndex += 1
        }
        
        currentURL = url
        selectedItems.removeAll()
        loadItems()
    }
    
    func goBack() {
        guard canGoBack else { return }
        currentHistoryIndex -= 1
        currentURL = navigationHistory[currentHistoryIndex]
        selectedItems.removeAll()
        loadItems()
    }
    
    func goForward() {
        guard canGoForward else { return }
        currentHistoryIndex += 1
        currentURL = navigationHistory[currentHistoryIndex]
        selectedItems.removeAll()
        loadItems()
    }
    
    func goUp() {
        guard canGoUp else { return }
        let parentURL = currentURL.deletingLastPathComponent()
        navigateTo(parentURL)
    }
    
    func refresh() {
        loadItems()
    }
    
    func loadItems() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Check if we have read permission for the directory
                guard fileManager.isReadableFile(atPath: currentURL.path) else {
                    await MainActor.run {
                        self.errorMessage = "Permission denied. Cannot read contents of '\(currentURL.lastPathComponent)'"
                        self.isLoading = false
                        PermissionHelper.showPermissionAlert(for: currentURL.lastPathComponent)
                    }
                    return
                }
                
                let urls = try fileManager.contentsOfDirectory(
                    at: currentURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .fileSizeKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .isHiddenKey
                    ],
                    options: showHiddenFiles ? [] : .skipsHiddenFiles
                )
                
                let fileItems = urls.compactMap { url -> FileItem? in
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [
                            .isDirectoryKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .isHiddenKey
                        ])
                        
                        return FileItem(
                            name: url.lastPathComponent,
                            url: url,
                            isDirectory: resourceValues.isDirectory ?? false,
                            size: Int64(resourceValues.fileSize ?? 0),
                            dateModified: resourceValues.contentModificationDate ?? Date(),
                            dateCreated: resourceValues.creationDate ?? Date(),
                            isHidden: resourceValues.isHidden ?? false
                        )
                    } catch {
                        // Skip files we can't read instead of failing completely
                        print("Warning: Could not read file \(url.lastPathComponent): \(error)")
                        return nil
                    }
                }
                
                await MainActor.run {
                    self.items = sortItems(fileItems)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    let errorMsg: String
                    if error.localizedDescription.contains("Operation not permitted") {
                        errorMsg = "Permission denied. This folder requires special access permissions."
                    } else if error.localizedDescription.contains("No such file") {
                        errorMsg = "Folder not found or has been moved."
                    } else {
                        errorMsg = "Error: \(error.localizedDescription)"
                    }
                    self.errorMessage = errorMsg
                    self.isLoading = false
                }
            }
        }
    }
    
    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        let sorted = items.sorted { item1, item2 in
            // Always put directories first
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            
            let result: Bool
            switch sortBy {
            case .name:
                result = item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            case .size:
                result = item1.size < item2.size
            case .dateModified:
                result = item1.dateModified < item2.dateModified
            case .type:
                result = item1.url.pathExtension.localizedCaseInsensitiveCompare(item2.url.pathExtension) == .orderedAscending
            }
            
            return sortAscending ? result : !result
        }
        
        return sorted
    }
    
    func setSortOption(_ option: SortOption) {
        if sortBy == option {
            sortAscending.toggle()
        } else {
            sortBy = option
            sortAscending = true
        }
        items = sortItems(items)
    }
    
    func openItem(_ item: FileItem) {
        if item.isDirectory {
            // Check if we can access the directory before navigating
            if fileManager.isReadableFile(atPath: item.url.path) {
                navigateTo(item.url)
            } else {
                errorMessage = "Permission denied. Cannot access '\(item.name)'"
                PermissionHelper.showPermissionAlert(for: item.name)
            }
        } else {
            // Open file with default application
            if fileManager.isReadableFile(atPath: item.url.path) {
                NSWorkspace.shared.open(item.url)
            } else {
                errorMessage = "Permission denied. Cannot open '\(item.name)'"
            }
        }
    }
    
    func selectItem(_ item: FileItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }
    
    func selectAll() {
        selectedItems = Set(items)
    }
    
    func deselectAll() {
        selectedItems.removeAll()
    }
    
    // MARK: - Clipboard Operations
    
    func copySelectedItems() {
        guard !selectedItems.isEmpty else { return }
        ClipboardManager.shared.copyItems(Array(selectedItems))
    }
    
    func cutSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        ClipboardManager.shared.cutItems(Array(selectedItems))
    }
    
    func pasteItems() {
        ClipboardManager.shared.pasteItems(to: currentURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refresh()
                case .failure(let error):
                    self.errorMessage = "Paste failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    var canPaste: Bool {
        ClipboardManager.shared.canPaste
    }
    
    // MARK: - Keyboard Shortcuts
    
    func handleKeyboardShortcut(_ key: String, modifiers: EventModifiers) -> Bool {
        if modifiers.contains(.command) {
            switch key.lowercased() {
            case "c":
                copySelectedItems()
                return true
            case "x":
                cutSelectedItems()
                return true
            case "v":
                if canPaste {
                    pasteItems()
                }
                return true
            case "a":
                selectAll()
                return true
            case "f":
                // Will be handled by search view
                return false
            default:
                return false
            }
        }
        
        switch key {
        case "Delete", "Backspace", "\u{7F}":
            moveSelectedItemsToTrash()
            return true
        case "Return", "Enter":
            if selectedItems.count == 1 {
                openItem(selectedItems.first!)
                return true
            }
        default:
            return false
        }
        
        return false
    }
    
    func deleteSelectedItems() {
        moveSelectedItemsToTrash()
    }
    
    // MARK: - Search Operations
    
    func performSearch(_ query: String, scope: SearchScope? = nil) {
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        
        searchText = query
        if let scope = scope {
            searchScope = scope
        }
        isSearching = true
        isInSearchMode = true
        
        Task {
            let results = await searchFiles(query: query, scope: searchScope)
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    func clearSearch() {
        searchText = ""
        isSearching = false
        isInSearchMode = false
        searchResults = []
    }
    
    var displayItems: [FileItem] {
        return isInSearchMode ? searchResults : items
    }
    
    private func searchFiles(query: String, scope: SearchScope) async -> [FileItem] {
        var results: [FileItem] = []
        let fileManager = FileManager.default
        
        let searchURLs: [URL]
        let searchOptions: FileManager.DirectoryEnumerationOptions
        
        switch scope {
        case .currentFolder:
            searchURLs = [currentURL]
            searchOptions = showHiddenFiles ? [.skipsSubdirectoryDescendants] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            
        case .currentFolderRecursive:
            searchURLs = [currentURL]
            searchOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            
        case .system:
            searchURLs = [
                fileManager.homeDirectoryForCurrentUser,
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications")
            ]
            searchOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        }
        
        for searchURL in searchURLs {
            await searchInDirectory(
                url: searchURL,
                query: query,
                options: searchOptions,
                results: &results
            )
        }
        
        return sortItems(results)
    }
    
    private func searchInDirectory(
        url: URL,
        query: String,
        options: FileManager.DirectoryEnumerationOptions,
        results: inout [FileItem]
    ) async {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .isHiddenKey
            ],
            options: options
        ) else { return }
        
        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent
            
            if fileName.localizedCaseInsensitiveContains(query) {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .fileSizeKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .isHiddenKey
                    ])
                    
                    let item = FileItem(
                        name: fileName,
                        url: fileURL,
                        isDirectory: resourceValues.isDirectory ?? false,
                        size: Int64(resourceValues.fileSize ?? 0),
                        dateModified: resourceValues.contentModificationDate ?? Date(),
                        dateCreated: resourceValues.creationDate ?? Date(),
                        isHidden: resourceValues.isHidden ?? false
                    )
                    
                    results.append(item)
                } catch {
                    continue
                }
            }
        }
    }
    
    private func moveSelectedItemsToTrash() {
        guard !selectedItems.isEmpty else { return }
        
        for item in selectedItems {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            } catch {
                errorMessage = "Failed to move item to trash: \(error.localizedDescription)"
            }
        }
        selectedItems.removeAll()
        refresh()
    }
}

enum SortOption: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case dateModified = "Date Modified"
    case type = "Type"
    
    var icon: String {
        switch self {
        case .name:
            return "textformat"
        case .size:
            return "externaldrive"
        case .dateModified:
            return "calendar"
        case .type:
            return "doc"
        }
    }
}