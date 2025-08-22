import SwiftUI

struct ContentView: View {
    @State private var useTabs = true
    
    var body: some View {
        Group {
            if useTabs {
                TabbedContentView()
            } else {
                SingleWindowContentView()
            }
        }
        .navigationTitle("File Explorer")
    }
}

struct TabbedContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .home
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(selectedItem: $selectedSidebarItem, fileManager: nil)
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
                
                Button(action: { fileManager.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!fileManager.canGoForward)
                
                Button(action: { fileManager.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!fileManager.canGoUp)
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { fileManager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                
                Menu {
                    Button("List") { fileManager.viewMode = .list }
                    Button("Icons") { fileManager.viewMode = .icons }
                    Button("Columns") { fileManager.viewMode = .columns }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
    }
}

