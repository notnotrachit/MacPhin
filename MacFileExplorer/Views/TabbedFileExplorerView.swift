import SwiftUI

class Tab: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    @Published var title: String
    @Published var url: URL
    let fileManager: FileExplorerManager
    
    init(title: String, url: URL) {
        self.title = title
        self.url = url
        self.fileManager = FileExplorerManager()
        
        // Navigate to URL after initialization
        DispatchQueue.main.async {
            self.fileManager.navigateTo(url)
        }
    }
    
    nonisolated static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TabbedFileExplorerView: View {
    @State private var tabs: [Tab] = []
    @State private var selectedTab: Tab?
    @Binding var selectedSidebarItem: SidebarItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar - always show
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabView(
                            tab: tab,
                            isSelected: selectedTab?.id == tab.id,
                            onSelect: { 
                                selectedTab = tab
                                print("Selected tab: \(tab.title)") // Debug
                            },
                            onClose: { closeTab(tab) }
                        )
                    }
                        
                        // New tab button
                        Button {
                            print("Add new tab button clicked") // Debug
                            addNewTab()
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 30, height: 30)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            .frame(height: 40) // Fixed height for tab bar
            
            // Main content
            if let currentTab = selectedTab {
                FileExplorerView(
                    fileManager: currentTab.fileManager,
                    selectedSidebarItem: selectedSidebarItem
                )
            } else {
                VStack {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No tabs open")
                        .foregroundColor(.secondary)
                    Button("Open New Tab") {
                        addNewTab()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            print("TabbedFileExplorerView appeared") // Debug
            if tabs.isEmpty {
                print("No tabs, adding initial tab") // Debug
                addNewTab()
            }
        }
        .toolbar {
            // Hidden keyboard shortcuts for tab management
            ToolbarItemGroup(placement: .automatic) {
                Button("New Tab") { addNewTab() }
                    .keyboardShortcut("t", modifiers: .command)
                    .hidden()
                
                Button("Close Tab") { 
                    if let currentTab = selectedTab {
                        closeTab(currentTab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
                
                // Tab switching shortcuts (1-9)
                ForEach(1..<10) { index in
                    Button("Tab \(index)") {
                        if index <= tabs.count {
                            selectedTab = tabs[index - 1]
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                    .hidden()
                }
            }
        }
        .onChange(of: selectedSidebarItem) { newValue in
            if let item = newValue, let currentTab = selectedTab {
                DispatchQueue.main.async {
                    currentTab.fileManager.navigateTo(item.url)
                    self.updateTabTitle(currentTab)
                }
            }
        }
    }
    
    private func addNewTab() {
        print("addNewTab() called") // Debug
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        
        let newTab = Tab(title: "Home", url: homeURL)
        tabs.append(newTab)
        selectedTab = newTab
        print("New tab added. Total tabs: \(tabs.count)") // Debug
        print("Selected tab: \(selectedTab?.title ?? "none")") // Debug
    }
    
    private func closeTab(_ tab: Tab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: index)
            
            if selectedTab?.id == tab.id {
                if !tabs.isEmpty {
                    selectedTab = tabs[max(0, index - 1)]
                } else {
                    selectedTab = nil
                }
            }
        }
    }
    
    private func updateTabTitle(_ tab: Tab) {
        DispatchQueue.main.async {
            let newTitle = tab.fileManager.currentURL.lastPathComponent.isEmpty ? 
                          "Root" : tab.fileManager.currentURL.lastPathComponent
            tab.title = newTitle
        }
    }
}

struct TabView: View {
    let tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            
            if isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.2) : 
            isHovered ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}