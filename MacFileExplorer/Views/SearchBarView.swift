import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    @Binding var searchScope: SearchScope
    @Binding var fileTypeFilter: String
    @Binding var sizeOperator: String
    @Binding var sizeValue: Double
    @Binding var sizeUnit: String
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var useRegex: Bool
    @Binding var searchInContent: Bool
    @State private var showAdvancedFilters = false
    @FocusState private var isSearchFieldFocused: Bool
    
    let onSearch: (String, SearchScope) -> Void
    let onClear: () -> Void
    
    private let sizeOperators = ["=", ">", "<", ">=", "<="]
    private let sizeUnits = ["Bytes", "KB", "MB", "GB"]
    
    var body: some View {
        VStack(spacing: 8) {
            // Search input
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search files and folders...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            if !searchText.isEmpty {
                                onSearch(searchText, searchScope)
                            }
                        }
                        .onChange(of: searchText) { newValue in
                            if newValue.isEmpty {
                                onClear()
                            } else {
                                onSearch(newValue, searchScope)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            onClear()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        
                        Button("Advanced...") {
                            withAnimation {
                                showAdvancedFilters.toggle()
                            }
                            if showAdvancedFilters && !searchText.isEmpty {
                                onSearch(searchText, searchScope)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSearchFieldFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                
                if isSearching {
                    Button("Cancel") {
                        searchText = ""
                        onClear()
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // Search scope picker
            HStack {
                Text("Search in:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Search Scope", selection: $searchScope) {
                    Text("This Folder").tag(SearchScope.currentFolder)
                    Text("This Folder + Subfolders").tag(SearchScope.currentFolderRecursive)
                    Text("Entire System").tag(SearchScope.system)
                }
                .pickerStyle(.segmented)
                .disabled(isSearching)
                .onChange(of: searchScope) { _ in
                    if !searchText.isEmpty {
                        onSearch(searchText, searchScope)
                    }
                }
                
                Spacer()
            }
            
            // Advanced filters section
            if !searchText.isEmpty && showAdvancedFilters {
                VStack(spacing: 12) {
                    Text("Advanced Filters")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // File type filter
                    HStack {
                        Text("File Type:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., pdf", text: $fileTypeFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(isSearching)
                            .onChange(of: fileTypeFilter) { _ in
                                if !searchText.isEmpty {
                                    onSearch(searchText, searchScope)
                                }
                            }
                        Spacer()
                    }
                    
                    // Size filter
                    HStack {
                        Text("Size:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Op", selection: $sizeOperator) {
                            ForEach(sizeOperators, id: \.self) { op in
                                Text(op).tag(op)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isSearching)
                        .frame(width: 50)
                        
                        TextField("Value", value: $sizeValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .disabled(isSearching)
                        
                        Picker("Unit", selection: $sizeUnit) {
                            ForEach(sizeUnits, id: \.self) { unit in
                                Text(unit).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isSearching)
                        .frame(width: 60)
                        
                        .onChange(of: sizeOperator) { _ in
                            if !searchText.isEmpty {
                                onSearch(searchText, searchScope)
                            }
                        }
                        .onChange(of: sizeValue) { _ in
                            if !searchText.isEmpty {
                                onSearch(searchText, searchScope)
                            }
                        }
                        .onChange(of: sizeUnit) { _ in
                            if !searchText.isEmpty {
                                onSearch(searchText, searchScope)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Date filter
                    HStack {
                        Text("Date Modified:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        DatePicker("From", selection: Binding(get: { dateFrom ?? Date.distantPast }, set: { dateFrom = $0 }), in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .disabled(isSearching)
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: dateFrom) { _ in
                                if !searchText.isEmpty {
                                    onSearch(searchText, searchScope)
                                }
                            }
                        
                        Text("To")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        DatePicker("To", selection: Binding(get: { dateTo ?? Date() }, set: { dateTo = $0 }), in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .disabled(isSearching)
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: dateTo) { _ in
                                if !searchText.isEmpty {
                                    onSearch(searchText, searchScope)
                                }
                            }
                        
                        Spacer()
                    }
                    
                    // Regex and Content search toggles
                    HStack {
                        Toggle("Regex", isOn: $useRegex)
                            .toggleStyle(.switch)
                            .disabled(isSearching)
                            .onChange(of: useRegex) { _ in
                                if !searchText.isEmpty {
                                    onSearch(searchText, searchScope)
                                }
                            }
                        
                        Toggle("Search in Content", isOn: $searchInContent)
                            .toggleStyle(.switch)
                            .disabled(isSearching)
                            .onChange(of: searchInContent) { _ in
                                if !searchText.isEmpty {
                                    onSearch(searchText, searchScope)
                                }
                            }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearching)
        .animation(.easeInOut(duration: 0.2), value: searchText)
        .animation(.easeInOut(duration: 0.2), value: showAdvancedFilters)
    }
}

struct GlobalSearchView: View {
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchScope: SearchScope = .currentFolder
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Search controls
            VStack(spacing: 12) {
                SearchBarView(
                    searchText: $searchText,
                    isSearching: $isSearching,
                    searchScope: $searchScope,
                    fileTypeFilter: $fileManager.fileTypeFilter,
                    sizeOperator: $fileManager.sizeOperator,
                    sizeValue: $fileManager.sizeValue,
                    sizeUnit: $fileManager.sizeUnit,
                    dateFrom: $fileManager.dateFrom,
                    dateTo: $fileManager.dateTo,
                    useRegex: $fileManager.useRegex,
                    searchInContent: $fileManager.searchInContent,
                    onSearch: { query, scope in
                        performSearch(query)
                    },
                    onClear: clearSearch
                )
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // Search results
            if isSearching {
                VStack {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            } else if !searchResults.isEmpty {
                List(searchResults, id: \.id) { result in
                    SearchResultRowView(result: result, fileManager: fileManager)
                }
                .listStyle(.plain)
            } else if !searchText.isEmpty {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Try adjusting your search terms or scope")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search for files and folders")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Enter search terms above to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func performSearch(_ query: String) {
        guard !query.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        Task {
            let results = await searchFiles(query: query, scope: searchScope)
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    private func clearSearch() {
        searchResults = []
        isSearching = false
    }
    
    private func searchFiles(query: String, scope: SearchScope) async -> [SearchResult] {
        var results: [SearchResult] = []
        let fileManager = FileManager.default
        
        let searchURLs: [URL]
        switch scope {
        case .currentFolder:
            searchURLs = [self.fileManager.currentURL]
        case .currentFolderRecursive:
            searchURLs = [self.fileManager.currentURL]
        case .system:
            searchURLs = [
                fileManager.homeDirectoryForCurrentUser,
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications")
            ]
        }
        
        for searchURL in searchURLs {
            await searchInDirectory(url: searchURL, query: query, recursive: scope != .currentFolder, results: &results)
        }
        
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    private func searchInDirectory(url: URL, query: String, recursive: Bool, results: inout [SearchResult]) async {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        ) else { return }
        
        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent
            
            if fileName.localizedCaseInsensitiveContains(query) {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    
                    let relevanceScore = calculateRelevanceScore(fileName: fileName, query: query)
                    
                    let result = SearchResult(
                        id: UUID(),
                        name: fileName,
                        url: fileURL,
                        isDirectory: resourceValues.isDirectory ?? false,
                        size: Int64(resourceValues.fileSize ?? 0),
                        dateModified: resourceValues.contentModificationDate ?? Date(),
                        relevanceScore: relevanceScore
                    )
                    
                    results.append(result)
                } catch {
                    continue
                }
            }
        }
    }
    
    private func calculateRelevanceScore(fileName: String, query: String) -> Double {
        let lowercaseFileName = fileName.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // Exact match gets highest score
        if lowercaseFileName == lowercaseQuery {
            return 1.0
        }
        
        // Starts with query gets high score
        if lowercaseFileName.hasPrefix(lowercaseQuery) {
            return 0.8
        }
        
        // Contains query gets medium score
        if lowercaseFileName.contains(lowercaseQuery) {
            return 0.6
        }
        
        // Fuzzy match gets lower score
        return 0.3
    }
}

struct SearchResult {
    let id: UUID
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let dateModified: Date
    let relevanceScore: Double
    
    var displaySize: String {
        if isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct SearchResultRowView: View {
    let result: SearchResult
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        HStack {
            Image(systemName: result.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(result.isDirectory ? .blue : .gray)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(result.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.displaySize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(result.dateModified, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if result.isDirectory {
                fileManager.navigateTo(result.url)
            } else {
                NSWorkspace.shared.open(result.url)
            }
        }
        .onTapGesture {
            // Navigate to parent directory and select file
            fileManager.navigateTo(result.url.deletingLastPathComponent())
        }
        .contextMenu {
            Button("Open") {
                if result.isDirectory {
                    fileManager.navigateTo(result.url)
                } else {
                    NSWorkspace.shared.open(result.url)
                }
            }
            
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(result.url.path, inFileViewerRootedAtPath: "")
            }
            
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url.path, forType: .string)
            }
        }
    }
}

enum SearchScope: String, CaseIterable {
    case currentFolder = "Current Folder"
    case currentFolderRecursive = "Current & Subfolders"
    case system = "Entire System"
}
