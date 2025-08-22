import SwiftUI

struct FileExplorerView: View {
    @ObservedObject var fileManager: FileExplorerManager
    let selectedSidebarItem: SidebarItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Address bar
            AddressBarView(fileManager: fileManager)
            
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
            } else {
                switch fileManager.viewMode {
                case .list:
                    FileListView(fileManager: fileManager)
                case .icons:
                    FileIconView(fileManager: fileManager)
                case .columns:
                    FileColumnView(fileManager: fileManager)
                }
            }
        }
        .navigationTitle(fileManager.currentURL.lastPathComponent.isEmpty ? "Root" : fileManager.currentURL.lastPathComponent)
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

