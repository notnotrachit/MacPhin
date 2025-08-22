import SwiftUI
import QuickLook
import AppKit

struct QuickPreviewView: View {
    let item: FileItem
    @State private var showingPreview = false
    
    var body: some View {
        VStack {
            if item.isDirectory {
                VStack(spacing: 16) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                    
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Type", value: "Folder")
                        DetailRow(label: "Location", value: item.url.deletingLastPathComponent().path)
                        DetailRow(label: "Created", value: DateFormatter.localizedString(from: item.dateCreated, dateStyle: .medium, timeStyle: .short))
                        DetailRow(label: "Modified", value: DateFormatter.localizedString(from: item.dateModified, dateStyle: .medium, timeStyle: .short))
                    }
                }
            } else {
                VStack(spacing: 16) {
                    // Large thumbnail
                    FileThumbnailView(item: item, size: CGSize(width: 200, height: 150))
                    
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Type", value: item.url.pathExtension.uppercased())
                        DetailRow(label: "Size", value: item.displaySize)
                        DetailRow(label: "Created", value: DateFormatter.localizedString(from: item.dateCreated, dateStyle: .medium, timeStyle: .short))
                        DetailRow(label: "Modified", value: DateFormatter.localizedString(from: item.dateModified, dateStyle: .medium, timeStyle: .short))
                        DetailRow(label: "Location", value: item.url.deletingLastPathComponent().path)
                    }
                    
                    if canPreview(item) {
                        Button("Quick Look") {
                            showQuickLook()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingPreview) {
            QuickLookPreview(url: item.url)
        }
    }
    
    private func canPreview(_ item: FileItem) -> Bool {
        let previewableExtensions = [
            "pdf", "txt", "rtf", "md", "html", "xml", "json",
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic",
            "mp4", "mov", "avi", "m4v",
            "mp3", "wav", "aac", "m4a",
            "doc", "docx", "xls", "xlsx", "ppt", "pptx"
        ]
        return previewableExtensions.contains(item.url.pathExtension.lowercased())
    }
    
    private func showQuickLook() {
        // Use NSWorkspace to open with Quick Look
        NSWorkspace.shared.open(item.url)
    }
}

struct QuickLookPreview: View {
    let url: URL
    
    var body: some View {
        VStack {
            Text("Quick Look Preview")
                .font(.headline)
            Text("File: \(url.lastPathComponent)")
                .foregroundColor(.secondary)
            
            Button("Open with Quick Look") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}