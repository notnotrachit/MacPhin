import SwiftUI

struct FileExplorerView: View {
    @ObservedObject var fileManager: FileExplorerManager
    let selectedSidebarItem: SidebarItem?
    @State private var showingSearch = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Address bar with integrated search
            VStack(spacing: 0) {
                AddressBarView(fileManager: fileManager)
                
                if showingSearch {
                    SearchBarView(
                        searchText: $fileManager.searchText,
                        isSearching: $fileManager.isSearching,
                        searchScope: $fileManager.searchScope,
                        onSearch: { query, scope in
                            fileManager.performSearch(query, scope: scope)
                        },
                        onClear: {
                            fileManager.clearSearch()
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            
            Divider()
            
            // Main content
            if fileManager.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = fileManager.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        fileManager.refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fileManager.displayItems.isEmpty && fileManager.isInSearchMode {
                // Search results empty state
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Try different search terms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch fileManager.viewMode {
                case .list:
                    FileListView(fileManager: fileManager)
                        .onFileDrop(fileManager: fileManager)
                case .icons:
                    FileIconView(fileManager: fileManager)
                        .onFileDrop(fileManager: fileManager)
                case .columns:
                    FileColumnView(fileManager: fileManager)
                        .onFileDrop(fileManager: fileManager)
                }
            }
        }
        .navigationTitle(fileManager.isInSearchMode ? "Search Results" : (fileManager.currentURL.lastPathComponent.isEmpty ? "Root" : fileManager.currentURL.lastPathComponent))
        .focusable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingSearch.toggle()
                    }
                }) {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Search (⌘F)")
            }
            
            // Hidden buttons for keyboard shortcuts
            ToolbarItemGroup(placement: .automatic) {
                Button("Copy") { fileManager.copySelectedItems() }
                    .keyboardShortcut("c", modifiers: .command)
                    .hidden()
                
                Button("Cut") { fileManager.cutSelectedItems() }
                    .keyboardShortcut("x", modifiers: .command)
                    .hidden()
                
                Button("Paste") { fileManager.pasteItems() }
                    .keyboardShortcut("v", modifiers: .command)
                    .hidden()
                
                Button("Select All") { fileManager.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)
                    .hidden()
                
                Button("Delete") { 
                    fileManager.deleteSelectedItems()
                }
                .keyboardShortcut(.delete)
                .hidden()
            }
        }
    }
    
}

struct AddressBarView: View {
    @ObservedObject var fileManager: FileExplorerManager
    @State private var isEditing = false
    @State private var editingPath = ""
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("Path", text: $editingPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let url = URL(fileURLWithPath: editingPath)
                        if Foundation.FileManager.default.fileExists(atPath: url.path) {
                            fileManager.navigateTo(url)
                        }
                        isEditing = false
                    }
                    .onAppear {
                        editingPath = fileManager.currentURL.path
                    }
                
                Button("Cancel") {
                    isEditing = false
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        let pathComponents = fileManager.currentURL.pathComponents
                        ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            
                            Button(component == "/" ? "Root" : component) {
                                let newPath = pathComponents[0...index].joined(separator: "/")
                                let url = URL(fileURLWithPath: newPath.isEmpty ? "/" : newPath)
                                fileManager.navigateTo(url)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(index == pathComponents.count - 1 ? .primary : .blue)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onTapGesture {
                    isEditing = true
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

