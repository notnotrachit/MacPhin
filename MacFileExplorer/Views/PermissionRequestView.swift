import SwiftUI

struct PermissionRequestView: View {
    @Binding var isPresented: Bool
    let onGranted: () -> Void
    let onDenied: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            // Title
            Text("Full Disk Access Required")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Description
            VStack(spacing: 12) {
                Text("To provide the best file browsing experience, this app needs Full Disk Access.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Browse all folders without permission prompts")
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Search across your entire system")
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Access system directories and applications")
                    }
                }
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Instructions
            VStack(spacing: 8) {
                Text("How to grant access:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Click 'Open System Preferences' below")
                    Text("2. Navigate to Privacy & Security → Full Disk Access")
                    Text("3. Click the lock to make changes")
                    Text("4. Add this app to the list")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Continue with Limited Access") {
                    isPresented = false
                    onDenied()
                }
                .buttonStyle(.bordered)
                
                Button("Grant Permissions") {
                    PermissionHelper.shared.requestAllPermissions { granted in
                        DispatchQueue.main.async {
                            isPresented = false
                            if granted {
                                onGranted()
                            } else {
                                onDenied()
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}

struct PermissionStatusView: View {
    @State private var hasUserDataAccess = false
    @State private var hasFullDiskAccess = false
    @State private var isCheckingPermissions = true
    
    var body: some View {
        HStack {
            let hasGoodAccess = hasUserDataAccess || hasFullDiskAccess
            
            Image(systemName: hasGoodAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundColor(hasGoodAccess ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if !hasGoodAccess {
                    Text("Folders may require permission")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if !hasGoodAccess {
                Button("Grant Access") {
                    PermissionHelper.shared.requestAllPermissions { _ in
                        checkPermissions()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            checkPermissions()
        }
    }
    
    private var statusText: String {
        if hasFullDiskAccess {
            return "Full System Access"
        } else if hasUserDataAccess {
            return "User Folders Access"
        } else {
            return "Limited File Access"
        }
    }
    
    private func checkPermissions() {
        isCheckingPermissions = true
        DispatchQueue.global(qos: .userInitiated).async {
            let userDataAccess = PermissionHelper.shared.checkUserDataAccess()
            let fullDiskAccess = PermissionHelper.shared.checkFullDiskAccess()
            
            DispatchQueue.main.async {
                self.hasUserDataAccess = userDataAccess
                self.hasFullDiskAccess = fullDiskAccess
                self.isCheckingPermissions = false
            }
        }
    }
}