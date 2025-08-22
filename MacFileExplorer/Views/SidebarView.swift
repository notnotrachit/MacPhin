import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    var fileManager: FileExplorerManager?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        List(selection: $selectedItem) {
            Section("Favorites") {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }
            
            Section("Devices") {
                Label("Macintosh HD", systemImage: "internaldrive")
                Label("External Drive", systemImage: "externaldrive")
                    .foregroundColor(.secondary)
            }
            
            Section("Network") {
                Label("Network", systemImage: "network")
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(SidebarListStyle())
        .focused($isFocused)
        .onChange(of: selectedItem) { newValue in
            if let item = newValue, let fileManager = fileManager {
                fileManager.navigateTo(item.url)
            }
        }
    }
}

