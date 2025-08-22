import Foundation
import AppKit

class PermissionHelper {
    static let shared = PermissionHelper()
    
    private init() {}
    func checkFullDiskAccess() -> Bool {
        // Test access to a protected directory
        let protectedPath = "/Library/Application Support"
        let fileManager = FileManager.default
        
        do {
            _ = try fileManager.contentsOfDirectory(atPath: protectedPath)
            return true
        } catch {
            return false
        }
    }
    
    func checkUserDataAccess() -> Bool {
        let fileManager = FileManager.default
        let userDataPaths = [
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.path,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
            fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first?.path
        ].compactMap { $0 }
        
        // Test if we can read these directories
        for path in userDataPaths {
            if !fileManager.isReadableFile(atPath: path) {
                return false
            }
        }
        return true
    }
    
    func requestUserDataAccess(completion: @escaping (Bool) -> Void) {
        // Pre-emptively access user data directories to trigger permission dialogs
        let fileManager = FileManager.default
        let userDataURLs = [
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var accessGranted = true
            
            for url in userDataURLs {
                do {
                    _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                } catch {
                    accessGranted = false
                }
            }
            
            DispatchQueue.main.async {
                completion(accessGranted)
            }
        }
    }
    
    func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        // First request user data access (this will trigger the individual folder dialogs)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "File Access Permissions Required"
            alert.informativeText = """
            To provide the best file browsing experience, this app needs access to your files and folders.
            
            You'll be asked to grant access to:
            • Desktop, Documents, Downloads folders
            • Pictures and other user directories
            
            This is a one-time setup to avoid repeated permission requests.
            """
            alert.addButton(withTitle: "Grant Access")
            alert.addButton(withTitle: "Continue with Limited Access")
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: "Folder Access")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Request user data access first
                self.requestUserDataAccess { userDataGranted in
                    // Then check if we also have full disk access
                    let hasFullDiskAccess = self.checkFullDiskAccess()
                    
                    if !hasFullDiskAccess {
                        // If we don't have full disk access, offer to grant it
                        self.offerFullDiskAccess { fullDiskGranted in
                            completion(userDataGranted || fullDiskGranted)
                        }
                    } else {
                        completion(userDataGranted || hasFullDiskAccess)
                    }
                }
            } else {
                completion(false)
            }
        }
    }
    
    private func offerFullDiskAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Enhanced Access Available"
            alert.informativeText = """
            For even better performance and to access system directories, you can also grant Full Disk Access.
            
            This is optional but recommended for power users who want to:
            • Browse system directories (/Library, /System)
            • Search across the entire system
            • Access application bundles and system files
            """
            alert.addButton(withTitle: "Grant Full Disk Access")
            alert.addButton(withTitle: "Continue")
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Security")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openFullDiskAccessSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    completion(self.checkFullDiskAccess())
                }
            } else {
                completion(false)
            }
        }
    }
    
    private func openFullDiskAccessSettings() {
        // Try modern System Settings first (macOS 13+)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        
        // Fallback to older System Preferences
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    static func requestFileAccess(for url: URL, completion: @escaping (Bool) -> Void) {
        // First check if we have any access
        if PermissionHelper.shared.checkFullDiskAccess() || PermissionHelper.shared.checkUserDataAccess() {
            completion(true)
            return
        }
        
        // If not, request all permissions instead of individual folder access
        PermissionHelper.shared.requestAllPermissions(completion: completion)
    }
    
    static func showPermissionAlert(for path: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Access Denied"
            alert.informativeText = "Cannot access '\(path)'. This may require additional permissions."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Grant Permissions")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                PermissionHelper.shared.requestAllPermissions { _ in
                    // Permission request completed
                }
            }
        }
    }
}