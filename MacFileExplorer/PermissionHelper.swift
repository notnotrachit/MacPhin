import Foundation
import AppKit

class PermissionHelper {
    static func requestFileAccess(for url: URL, completion: @escaping (Bool) -> Void) {
        // For macOS, we can try to access the file and handle the error gracefully
        let fileManager = FileManager.default
        
        // Check if we already have access
        if fileManager.isReadableFile(atPath: url.path) {
            completion(true)
            return
        }
        
        // Show an alert explaining the permission issue
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required"
            alert.informativeText = "This app needs permission to access '\(url.lastPathComponent)'. You may need to grant Full Disk Access in System Preferences > Security & Privacy > Privacy > Full Disk Access."
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Preferences to Privacy settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            completion(false)
        }
    }
    
    static func showPermissionAlert(for path: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Access Denied"
            alert.informativeText = "Cannot access '\(path)'. This may require Full Disk Access permission in System Preferences."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open System Preferences")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}