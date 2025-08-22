import Foundation
import SwiftUI

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let dateModified: Date
    let dateCreated: Date
    let isHidden: Bool
    
    var displaySize: String {
        if isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "txt", "rtf", "md":
            return "doc.text.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv":
            return "video.fill"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "app":
            return "app.fill"
        case "swift":
            return "swift"
        case "py":
            return "terminal.fill"
        case "js", "html", "css":
            return "globe"
        default:
            return "doc.fill"
        }
    }
    
    var iconColor: Color {
        if isDirectory {
            return .blue
        }
        
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "txt", "rtf", "md":
            return .primary
        case "pdf":
            return .red
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return .green
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "wav", "aac", "flac":
            return .orange
        case "zip", "rar", "7z", "tar", "gz":
            return .brown
        case "app":
            return .blue
        case "swift":
            return .orange
        case "py":
            return .yellow
        case "js", "html", "css":
            return .blue
        default:
            return .gray
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case desktop = "Desktop"
    case documents = "Documents"
    case downloads = "Downloads"
    case applications = "Applications"
    case pictures = "Pictures"
    case music = "Music"
    case movies = "Movies"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .desktop:
            return "desktopcomputer"
        case .documents:
            return "doc.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .applications:
            return "app.fill"
        case .pictures:
            return "photo.fill"
        case .music:
            return "music.note"
        case .movies:
            return "video.fill"
        }
    }
    
    var url: URL {
        let fileManager = Foundation.FileManager.default
        switch self {
        case .home:
            return fileManager.homeDirectoryForCurrentUser
        case .desktop:
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        case .documents:
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        case .downloads:
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        case .applications:
            return URL(fileURLWithPath: "/Applications")
        case .pictures:
            return fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        case .music:
            return fileManager.urls(for: .musicDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        case .movies:
            return fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        }
    }
}

enum ViewMode: String, CaseIterable {
    case list = "List"
    case icons = "Icons"
    case columns = "Columns"
}