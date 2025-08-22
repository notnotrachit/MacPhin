import SwiftUI

struct FileExplorerView: View {
    @ObservedObject var fileManager: FileExplorerManager
    let selectedSidebarItem: SidebarItem?
    @State private var showingSearch = false
    @FocusState private var focusedField: FocusedField?
    
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
        .focused($focusedField, equals: .fileList)
        .onKeyDown { event in
            let key = keyNameFromEvent(event)
            let modifiers = eventModifiersFromNSEvent(event)
            return fileManager.handleKeyPress(key, modifiers: modifiers)
        }
        .onChange(of: focusedField) { newValue in
            fileManager.focusedField = newValue
        }
        .onChange(of: fileManager.displayItems) { _ in
            fileManager.updateKeyboardSelectedIndex()
        }
        .onAppear {
            fileManager.resetKeyboardSelection()
            focusedField = .fileList
        }
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
    
    // MARK: - Key Event Helpers
    private func keyNameFromEvent(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 126: return "Up"
        case 125: return "Down"
        case 123: return "Left"
        case 124: return "Right"
        case 36: return "Return"
        case 49: return "Space"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        default: return event.charactersIgnoringModifiers ?? ""
        }
    }
    
    private func eventModifiersFromNSEvent(_ event: NSEvent) -> EventModifiers {
        var modifiers = EventModifiers()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}

// MARK: - Key Event View Modifier
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        self.background(KeyEventHandlingView(onKeyDown: action))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyEventNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let onKeyDown = onKeyDown, onKeyDown(event) {
            return // Event was handled
        }
        super.keyDown(with: event)
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
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

