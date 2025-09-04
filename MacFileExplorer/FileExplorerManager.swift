import Foundation
import SwiftUI

// MARK: - Focus Management
enum FocusedField: Hashable {
    case sidebar
    case fileList
    case searchBar
    case addressBar
}

// MARK: - Search Result Types
struct SearchResultItem {
    let fileItem: FileItem
    let relevanceScore: Double
    let matchType: MatchType
}

enum MatchType {
    case exactMatch
    case prefixMatch
    case containsMatch
    case fuzzyMatch
    case extensionMatch
    
    var priority: Int {
        switch self {
        case .exactMatch: return 5
        case .prefixMatch: return 4
        case .containsMatch: return 3
        case .extensionMatch: return 2
        case .fuzzyMatch: return 1
        }
    }
}

class FileExplorerManager: ObservableObject {
    @Published var currentURL: URL
    @Published var items: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var viewMode: ViewMode = .list
    @Published var sortBy: SortOption = .name
    @Published var sortAscending = true
    @Published var showHiddenFiles = false
    @Published var selectedItems: Set<FileItem> = [] {
        didSet {
            // Update selection lookup for O(1) access
            selectedItemsLookup = Set(selectedItems.map { $0.id })
        }
    }
    
    // Fast O(1) lookup for selection state
    @Published private(set) var selectedItemsLookup: Set<UUID> = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchResults: [FileItem] = []
    @Published var isInSearchMode = false
    @Published var searchScope: SearchScope = .currentFolder
    
    // Keyboard navigation properties
    @Published var focusedField: FocusedField? = nil
    @Published var keyboardSelectedIndex: Int = 0

    // Drag (marquee) selection properties
    @Published var isDragSelecting: Bool = false
    @Published var dragStartPoint: CGPoint = .zero
    @Published var dragCurrentPoint: CGPoint = .zero
    @Published var dragOriginalSelection: Set<FileItem> = []
    @Published var dragUnionMode: Bool = false // true when command is held during drag to union with existing selection
    @Published var debugMarquee: Bool = true
    
    // Search debouncing
    private var searchTask: Task<Void, Never>?
    
    @Published private(set) var navigationHistory: [URL] = []
    @Published private(set) var currentHistoryIndex = -1
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private let fileManager = Foundation.FileManager.default
    
    var canGoUp: Bool {
        currentURL.path != "/"
    }
    
    init() {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        self.currentURL = homeURL
        // Initialize navigation history with home directory
        self.navigationHistory = [homeURL]
        self.currentHistoryIndex = 0
        self.canGoBack = false
        self.canGoForward = false
        // Enable debug for marquee while developing selection behavior
        self.debugMarquee = true
        loadItems()
    }
    
    // MARK: - Keyboard Navigation Methods
    
    func moveSelectionUp() {
        let items = displayItems
        guard !items.isEmpty else { return }
        
        if keyboardSelectedIndex > 0 {
            keyboardSelectedIndex -= 1
            selectKeyboardItem()
        }
    }
    
    func moveSelectionDown() {
        let items = displayItems
        guard !items.isEmpty else { return }
        
        if keyboardSelectedIndex < items.count - 1 {
            keyboardSelectedIndex += 1
            selectKeyboardItem()
        }
    }
    
    func selectKeyboardItem() {
        let items = displayItems
        guard keyboardSelectedIndex < items.count else { return }
        
        let item = items[keyboardSelectedIndex]
        selectedItems = [item]
    }
    
    func openKeyboardSelectedItem() {
        let items = displayItems
        guard keyboardSelectedIndex < items.count else { return }
        
        let item = items[keyboardSelectedIndex]
        openItem(item)
    }
    
    func toggleKeyboardSelection() {
        let items = displayItems
        guard keyboardSelectedIndex < items.count else { return }
        
        let item = items[keyboardSelectedIndex]
        selectItem(item, withModifiers: [.command])
    }
    
    func selectRange(to index: Int) {
        let items = displayItems
        let startIndex = min(keyboardSelectedIndex, index)
        let endIndex = max(keyboardSelectedIndex, index)
        
        let selectedItems = Set(items[startIndex...endIndex])
        self.selectedItems = selectedItems
    }
    
    func updateKeyboardSelectedIndex() {
        let items = displayItems
        
        // Ensure selected index is within bounds
        keyboardSelectedIndex = min(keyboardSelectedIndex, max(0, items.count - 1))
        
        // If there's a selection, try to maintain it
        if let firstSelected = selectedItems.first,
           let index = items.firstIndex(of: firstSelected) {
            keyboardSelectedIndex = index
        }
    }
    
    func resetKeyboardSelection() {
        keyboardSelectedIndex = 0
        selectKeyboardItem()
    }
    
    
    func navigateTo(_ url: URL) {
        // If navigating to the same URL, do nothing
        if url == currentURL {
            return
        }
        
        // Clear search mode when navigating to a new location
        clearSearch()
        
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
        
        // Update navigation state
        canGoBack = currentHistoryIndex > 0
        canGoForward = currentHistoryIndex < navigationHistory.count - 1
        
        currentURL = url
        selectedItems.removeAll()
        loadItems()
    }
    
    func goBack() {
        guard currentHistoryIndex > 0 else { return }
        currentHistoryIndex -= 1
        currentURL = navigationHistory[currentHistoryIndex]
        
        // Update navigation state
        canGoBack = currentHistoryIndex > 0
        canGoForward = currentHistoryIndex < navigationHistory.count - 1
        
        selectedItems.removeAll()
        loadItems()
    }
    
    func goForward() {
        guard currentHistoryIndex < navigationHistory.count - 1 else { return }
        currentHistoryIndex += 1
        currentURL = navigationHistory[currentHistoryIndex]
        
        // Update navigation state
        canGoBack = currentHistoryIndex > 0
        canGoForward = currentHistoryIndex < navigationHistory.count - 1
        
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
                
                // Sort items on background thread to avoid blocking UI
                let sortedItems = sortItems(fileItems)
                
                await MainActor.run {
                    self.items = sortedItems
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
        
        // Sort on background thread for large folders
        Task {
            let sortedItems = sortItems(items)
            await MainActor.run {
                self.items = sortedItems
            }
        }
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
    
    func selectItem(_ item: FileItem, withModifiers modifiers: EventModifiers = []) {
        if modifiers.contains(.command) {
            // Command+click: toggle selection (add/remove from selection)
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
        } else if modifiers.contains(.shift) && !selectedItems.isEmpty {
            // Shift+click: select range - simplified for performance
            selectedItems.insert(item)
        } else {
            // Normal click: clear previous selection and select only the clicked item
            selectedItems = [item]
        }
    }
    
    func selectAll() {
        selectedItems = Set(items)
    }
    
    func deselectAll() {
        selectedItems.removeAll()
    }
    
    // Fast O(1) selection check
    func isItemSelected(_ item: FileItem) -> Bool {
        return selectedItemsLookup.contains(item.id)
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
    
    // MARK: - Keyboard Event Handling
    
    func handleKeyPress(_ key: String, modifiers: EventModifiers) -> Bool {
        // Handle arrow keys for navigation
        switch key {
        case "Up":
            if modifiers.contains(.shift) {
                let newIndex = max(0, keyboardSelectedIndex - 1)
                selectRange(to: newIndex)
                keyboardSelectedIndex = newIndex
            } else {
                moveSelectionUp()
            }
            return true
            
        case "Down":
            if modifiers.contains(.shift) {
                let items = displayItems
                let newIndex = min(items.count - 1, keyboardSelectedIndex + 1)
                selectRange(to: newIndex)
                keyboardSelectedIndex = newIndex
            } else {
                moveSelectionDown()
            }
            return true
            
        case "Left":
            if focusedField == .fileList && !modifiers.contains(.command) {
                focusedField = .sidebar
                return true
            }
            return false
            
        case "Right":
            if focusedField == .sidebar {
                focusedField = .fileList
                return true
            } else if focusedField == .fileList && isInSearchMode {
                focusedField = .searchBar
                return true
            }
            return false
            
        case "Return", "Enter":
            if focusedField == .fileList {
                openKeyboardSelectedItem()
                return true
            }
            return false
            
        case "Space":
            if focusedField == .fileList {
                toggleKeyboardSelection()
                return true
            }
            return false
            
        case "Tab":
            if modifiers.contains(.shift) {
                moveFocusPrevious()
            } else {
                moveFocusNext()
            }
            return true
            
        case "Escape":
            deselectAll()
            return true
            
        default:
            break
        }
        
        return handleKeyboardShortcut(key, modifiers: modifiers)
    }
    
    func moveFocusNext() {
        switch focusedField {
        case .sidebar:
            focusedField = .fileList
        case .fileList:
            if isInSearchMode {
                focusedField = .searchBar
            } else {
                focusedField = .sidebar
            }
        case .searchBar:
            focusedField = .addressBar
        case .addressBar:
            focusedField = .sidebar
        case .none:
            focusedField = .fileList
        }
    }
    
    func moveFocusPrevious() {
        switch focusedField {
        case .sidebar:
            focusedField = .addressBar
        case .fileList:
            focusedField = .sidebar
        case .searchBar:
            focusedField = .fileList
        case .addressBar:
            focusedField = .searchBar
        case .none:
            focusedField = .fileList
        }
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
            case "r":
                refresh()
                return true
            case "h":
                if modifiers.contains(.shift) {
                    showHiddenFiles.toggle()
                    loadItems()
                    return true
                }
                return false
            case "1":
                viewMode = .list
                return true
            case "2":
                viewMode = .smallIcons
                return true
            case "3":
                viewMode = .mediumIcons
                return true
            case "4":
                viewMode = .largeIcons
                return true
            case "5":
                viewMode = .columns
                return true
            case "n":
                createNewFolder()
                return true
            case "d":
                duplicateSelectedItems()
                return true
            default:
                return false
            }
        }
        
        if modifiers.contains(.command) && modifiers.contains(.shift) {
            switch key.lowercased() {
            case "c":
                copyPathToClipboard()
                return true
            case "r":
                revealInFinder()
                return true
            case "g":
                // Go to folder - would need UI implementation
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
    
    // MARK: - Additional Operations
    
    func createNewFolder() {
        let newFolderName = "New Folder"
        var finalName = newFolderName
        var counter = 1
        
        // Find unique name
        while fileManager.fileExists(atPath: currentURL.appendingPathComponent(finalName).path) {
            finalName = "\(newFolderName) \(counter)"
            counter += 1
        }
        
        let newFolderURL = currentURL.appendingPathComponent(finalName)
        
        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            refresh()
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
    
    func duplicateSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        for item in selectedItems {
            let originalURL = item.url
            let fileName = originalURL.lastPathComponent
            let fileExtension = originalURL.pathExtension
            let baseName = fileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
            
            var duplicateName = fileName.isEmpty ? "Copy of \(baseName)" : "Copy of \(baseName).\(fileExtension)"
            var counter = 1
            
            // Find unique name
            while fileManager.fileExists(atPath: currentURL.appendingPathComponent(duplicateName).path) {
                if fileExtension.isEmpty {
                    duplicateName = "Copy \(counter) of \(baseName)"
                } else {
                    duplicateName = "Copy \(counter) of \(baseName).\(fileExtension)"
                }
                counter += 1
            }
            
            let duplicateURL = currentURL.appendingPathComponent(duplicateName)
            
            do {
                try fileManager.copyItem(at: originalURL, to: duplicateURL)
            } catch {
                errorMessage = "Failed to duplicate \(fileName): \(error.localizedDescription)"
            }
        }
        
        refresh()
    }
    
    func copyPathToClipboard() {
        guard let firstSelected = selectedItems.first else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(firstSelected.url.path, forType: .string)
    }
    
    func revealInFinder() {
        guard let firstSelected = selectedItems.first else { return }
        NSWorkspace.shared.selectFile(firstSelected.url.path, inFileViewerRootedAtPath: "")
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
        
        // Cancel previous search
        searchTask?.cancel()
        
        searchText = query
        if let scope = scope {
            searchScope = scope
        }
        isSearching = true
        isInSearchMode = true
        
        // Debounce search for better performance
        searchTask = Task {
            // Small delay to avoid searching on every keystroke
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            
            guard !Task.isCancelled else { return }
            
            let results = await searchFiles(query: query, scope: searchScope)
            
            guard !Task.isCancelled else { return }
            
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
        
        // Use TaskGroup for concurrent searching with shared deduplication
        let allResults = await withTaskGroup(of: [SearchResultItem].self) { group in
            var combinedResults: [SearchResultItem] = []
            
            for searchURL in searchURLs {
                group.addTask {
                    var results: [SearchResultItem] = []
                    await self.searchInDirectory(
                        url: searchURL,
                        query: query,
                        options: searchOptions,
                        results: &results,
                        maxResults: 500 // Limit per directory
                    )
                    return results
                }
            }
            
            // Collect results and deduplicate by path as we go
            var seenGlobalPaths: Set<String> = []
            for await results in group {
                for result in results {
                    let path = result.fileItem.url.path
                    if !seenGlobalPaths.contains(path) {
                        seenGlobalPaths.insert(path)
                        combinedResults.append(result)
                    }
                }
            }
            return combinedResults
        }
        
        // Sort by relevance score and match type, but limit final results
        let sortedResults = allResults.sorted { result1, result2 in
            // First sort by match type priority
            if result1.matchType.priority != result2.matchType.priority {
                return result1.matchType.priority > result2.matchType.priority
            }
            // Then by relevance score
            if result1.relevanceScore != result2.relevanceScore {
                return result1.relevanceScore > result2.relevanceScore
            }
            // Finally by name
            return result1.fileItem.name.localizedCaseInsensitiveCompare(result2.fileItem.name) == .orderedAscending
        }
        
        // Return top 200 results to avoid UI performance issues
        return Array(sortedResults.prefix(200)).map { $0.fileItem }
    }
    
    private func searchInDirectory(
        url: URL,
        query: String,
        options: FileManager.DirectoryEnumerationOptions,
        results: inout [SearchResultItem],
        maxResults: Int = 1000
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
        
        var processedCount = 0
        let maxProcessed = 10000 // Limit how many files we process
        var seenPaths: Set<String> = [] // Track already processed file paths
        
        while let fileURL = enumerator.nextObject() as? URL {
            processedCount += 1
            
            // Stop if we've processed too many files or found enough results
            if processedCount > maxProcessed || results.count >= maxResults {
                break
            }
            
            // Skip if we've already processed this file path
            let filePath = fileURL.path
            if seenPaths.contains(filePath) {
                continue
            }
            seenPaths.insert(filePath)
            
            let fileName = fileURL.lastPathComponent
            
            // Quick filter: skip files that obviously don't match
            let lowercaseFileName = fileName.lowercased()
            let lowercaseQuery = query.lowercased()
            
            // Fast pre-filter to avoid expensive scoring
            let hasBasicMatch = lowercaseFileName.contains(lowercaseQuery) ||
                               (fileName as NSString).deletingPathExtension.lowercased().contains(lowercaseQuery) ||
                               (fileName as NSString).pathExtension.lowercased() == lowercaseQuery
            
            if !hasBasicMatch && query.count > 2 {
                // For longer queries, also check subsequence match
                let hasSubsequence = checkSimpleSubsequence(fileName: lowercaseFileName, query: lowercaseQuery)
                if !hasSubsequence {
                    continue
                }
            }
            
            // Calculate match score only for potential matches
            let matchScore = calculateFuzzyMatchScore(fileName: fileName, query: query)
            
            if matchScore > 0.1 {
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
                    
                    let searchResult = SearchResultItem(
                        fileItem: item,
                        relevanceScore: matchScore,
                        matchType: determineMatchType(fileName: fileName, query: query)
                    )
                    
                    results.append(searchResult)
                } catch {
                    continue
                }
            }
        }
    }
    
    private func checkSimpleSubsequence(fileName: String, query: String) -> Bool {
        var queryIndex = 0
        let queryChars = Array(query)
        
        for char in fileName {
            if queryIndex < queryChars.count && char == queryChars[queryIndex] {
                queryIndex += 1
            }
        }
        
        return queryIndex == queryChars.count
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
    
    // MARK: - Fuzzy Search Implementation
    
    private func calculateFuzzyMatchScore(fileName: String, query: String) -> Double {
        let lowercaseFileName = fileName.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // Fast early exits for common cases
        if lowercaseFileName == lowercaseQuery {
            return 1.0
        }
        
        if lowercaseFileName.hasPrefix(lowercaseQuery) {
            return 0.9
        }
        
        if lowercaseFileName.contains(lowercaseQuery) {
            // Simple position-based scoring without expensive distance calculation
            if let range = lowercaseFileName.range(of: lowercaseQuery) {
                let position = lowercaseFileName.distance(from: lowercaseFileName.startIndex, to: range.lowerBound)
                let positionScore = 1.0 - (Double(position) / Double(lowercaseFileName.count)) * 0.3
                return 0.8 * positionScore
            }
        }
        
        // Check filename without extension
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension.lowercased()
        if nameWithoutExtension == lowercaseQuery {
            return 0.95
        }
        
        if nameWithoutExtension.hasPrefix(lowercaseQuery) {
            return 0.85
        }
        
        if nameWithoutExtension.contains(lowercaseQuery) {
            return 0.75
        }
        
        // Extension match
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        if fileExtension == lowercaseQuery {
            return 0.7
        }
        
        // Only do expensive fuzzy matching for short queries and filenames
        if query.count <= 8 && fileName.count <= 50 {
            // Simple subsequence match (much faster than Levenshtein)
            let subsequenceScore = calculateSubsequenceMatch(fileName: lowercaseFileName, query: lowercaseQuery)
            if subsequenceScore > 0.4 {
                return subsequenceScore * 0.4
            }
        }
        
        return 0.0
    }
    
    private func determineMatchType(fileName: String, query: String) -> MatchType {
        let lowercaseFileName = fileName.lowercased()
        let lowercaseQuery = query.lowercased()
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension.lowercased()
        
        if lowercaseFileName == lowercaseQuery || nameWithoutExtension == lowercaseQuery {
            return .exactMatch
        }
        
        if lowercaseFileName.hasPrefix(lowercaseQuery) || nameWithoutExtension.hasPrefix(lowercaseQuery) {
            return .prefixMatch
        }
        
        if lowercaseFileName.contains(lowercaseQuery) {
            return .containsMatch
        }
        
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        if fileExtension == lowercaseQuery {
            return .extensionMatch
        }
        
        return .fuzzyMatch
    }
    
    // Removed expensive Levenshtein and acronym matching for performance
    
    private func calculateSubsequenceMatch(fileName: String, query: String) -> Double {
        let fileChars = Array(fileName)
        let queryChars = Array(query)
        
        var fileIndex = 0
        var queryIndex = 0
        var matchedChars = 0
        
        while fileIndex < fileChars.count && queryIndex < queryChars.count {
            if fileChars[fileIndex] == queryChars[queryIndex] {
                matchedChars += 1
                queryIndex += 1
            }
            fileIndex += 1
        }
        
        if matchedChars == queryChars.count {
            return Double(matchedChars) / Double(fileChars.count)
        }
        
        return 0.0
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