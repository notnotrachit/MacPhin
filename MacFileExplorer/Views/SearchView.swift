import SwiftUI

struct SearchView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var searchText = ""
    @State private var searchResults: [FileItem] = []
    @State private var isSearching = false
    
    var body: some View {
        VStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search files and folders...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                        searchResults = []
                    }
                }
            }
            .padding()
            
            // Search results
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchResults.isEmpty {
                List(searchResults, id: \.id) { item in
                    SearchResultRow(item: item, fileManager: fileManager)
                }
                .listStyle(.plain)
            } else if !searchText.isEmpty {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Enter search terms to find files and folders")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                searchResults = []
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        Task {
            let results = await searchFiles(in: fileManager.currentURL, searchTerm: searchText)
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    private func searchFiles(in directory: URL, searchTerm: String) async -> [FileItem] {
        var results: [FileItem] = []
        let fileManager = Foundation.FileManager.default
        
        func searchRecursively(in url: URL) {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .isHiddenKey
            ]) else { return }
            
            for case let fileURL as URL in enumerator {
                let fileName = fileURL.lastPathComponent
                if fileName.localizedCaseInsensitiveContains(searchTerm) {
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
        
        searchRecursively(in: directory)
        return results
    }
}

struct SearchResultRow: View {
    let item: FileItem
    @ObservedObject var fileManager: FileExplorerManager
    
    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .foregroundColor(item.iconColor)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(item.displaySize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            fileManager.openItem(item)
        }
        .onTapGesture {
            // Navigate to the parent directory and select the item
            fileManager.navigateTo(item.url.deletingLastPathComponent())
        }
    }
}

