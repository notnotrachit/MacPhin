import SwiftUI

struct ContentView: View {
    @State private var useTabs = true
    @State private var showingPermissionRequest = false
    @State private var hasCheckedPermissions = false
    
    var body: some View {
        Group {
            if useTabs {
                TabbedContentView()
            } else {
                SingleWindowContentView()
            }
        }
        .navigationTitle("File Explorer")
        .onAppear {
            checkPermissionsOnStartup()
        }
        .sheet(isPresented: $showingPermissionRequest) {
            PermissionRequestView(
                isPresented: $showingPermissionRequest,
                onGranted: {
                    // Permission granted, continue normally
                },
                onDenied: {
                    // Continue with limited access
                }
            )
        }
    }
    
    private func checkPermissionsOnStartup() {
        guard !hasCheckedPermissions else { return }
        hasCheckedPermissions = true
        
        // Check if we have both user data access and full disk access
        let hasUserDataAccess = PermissionHelper.shared.checkUserDataAccess()
        let hasFullDiskAccess = PermissionHelper.shared.checkFullDiskAccess()
        
        if !hasUserDataAccess && !hasFullDiskAccess {
            // Show permission request after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showingPermissionRequest = true
            }
        }
    }
}

struct TabbedContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .home
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar with permission status
            VStack {
                SidebarView(selectedItem: $selectedSidebarItem, fileManager: nil)
                
                Divider()
                
                // Permission status indicator
                PermissionStatusView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Tabbed content area
            TabbedFileExplorerView(selectedSidebarItem: $selectedSidebarItem)
        }
    }
}

struct SingleWindowContentView: View {
    @StateObject private var fileManager = FileExplorerManager()
    @State private var selectedSidebarItem: SidebarItem? = .home
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(selectedItem: $selectedSidebarItem, fileManager: fileManager)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Main content area
            FileExplorerView(fileManager: fileManager, selectedSidebarItem: selectedSidebarItem)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { fileManager.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!fileManager.canGoBack)
                .help("Back")
                
                Button(action: { fileManager.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!fileManager.canGoForward)
                .help("Forward")
                
                Button(action: { fileManager.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!fileManager.canGoUp)
                .help("Up")
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { fileManager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                
                Menu {
                    Button("List") { fileManager.viewMode = .list }
                    Button("Icons") { fileManager.viewMode = .icons }
                    Button("Columns") { fileManager.viewMode = .columns }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .help("View Options")
                
                // Clipboard operations
                Button(action: { fileManager.copySelectedItems() }) {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(fileManager.selectedItems.isEmpty)
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy (⌘C)")
                
                Button(action: { fileManager.cutSelectedItems() }) {
                    Image(systemName: "scissors")
                }
                .disabled(fileManager.selectedItems.isEmpty)
                .keyboardShortcut("x", modifiers: .command)
                .help("Cut (⌘X)")
                
                Button(action: { fileManager.pasteItems() }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .disabled(!fileManager.canPaste)
                .keyboardShortcut("v", modifiers: .command)
                .help("Paste (⌘V)")
                
                // Additional keyboard shortcuts (hidden buttons)
                Button("New Folder") { fileManager.createNewFolder() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                
                Button("Duplicate") { fileManager.duplicateSelectedItems() }
                    .keyboardShortcut("d", modifiers: .command)
                    .hidden()
                
                Button("List View") { fileManager.viewMode = .list }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                
                Button("Icon View") { fileManager.viewMode = .icons }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                
                Button("Column View") { fileManager.viewMode = .columns }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                
                Button("Toggle Hidden") { 
                    fileManager.showHiddenFiles.toggle()
                    fileManager.loadItems()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .hidden()
                
                Button("Copy Path") { fileManager.copyPathToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .hidden()
                
                Button("Reveal in Finder") { fileManager.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .hidden()
            }
        }
    }
}

