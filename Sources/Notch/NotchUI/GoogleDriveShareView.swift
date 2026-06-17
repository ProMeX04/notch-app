import SwiftUI
import NotchShelfFeature

struct GDriveCheckbox: View {
    let isChecked: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isChecked ? Color.blue : Color(white: 0.6), lineWidth: 2)
                    .background(isChecked ? Color.blue : Color.clear)
                    .frame(width: 18, height: 18)
                
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct GoogleDriveShareView: View {
    let item: NotchShelfItem
    let portalBaseURL: URL
    let onClose: () -> Void

    @State private var permissions: [GoogleDrivePermission] = []
    @State private var currentUser: GoogleDriveUser? = nil
    @State private var newEmail: String = ""
    @State private var newRole: String = "reader" // "reader", "commenter", "writer"
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var statusMessage: String? = nil
    @State private var toastMessage: String? = nil

    // Local General Access States for Optimistic UI updates
    @State private var localIsPublic: Bool = false
    @State private var localGeneralRole: String = "reader"

    // Settings States
    @State private var isShowingSettings: Bool = false
    @State private var writersCanShare: Bool = true
    @State private var limitAccess: Bool = false

    private var fileId: String {
        item.driveFileID ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShowingSettings {
                settingsView
            } else {
                mainShareView
            }
        }
        .frame(width: 480, height: 480)
        .background(Color(red: 0.118, green: 0.122, blue: 0.125)) // #1E1F20
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color(white: 0.2).opacity(0.95))
                    .cornerRadius(8)
                    .shadow(radius: 5)
                    .padding(.bottom, 80) // position it above the footer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastMessage)
        .task {
            await loadData()
        }
    }

    // Main Share View
    private var mainShareView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Share \"\(item.displayName)\"")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    if let url = URL(string: "https://support.google.com/drive/answer/2494822") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    isShowingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            if isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Error/Status messages
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }
                        
                        // Add People Field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("Add people, groups, and spaces", text: $newEmail)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(6)
                                    .onSubmit {
                                        handleAddPermission()
                                    }
                                
                                Picker("", selection: $newRole) {
                                    Text("Viewer").tag("reader")
                                    Text("Commenter").tag("commenter")
                                    Text("Editor").tag("writer")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 110)
                                .tint(.gray)
                                
                                Button(action: handleAddPermission) {
                                    Image(systemName: "plus")
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Color.blue)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // People with access section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("People with access")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            // Current user/Owner row
                            if let user = currentUser {
                                userRow(name: user.displayName, email: user.emailAddress, photoLink: user.photoLink, role: "Owner", isOwner: true, permissionId: nil)
                            } else if let ownerPermission = permissions.first(where: { $0.role == "owner" }) {
                                userRow(name: ownerPermission.displayName ?? "Owner", email: ownerPermission.emailAddress ?? "", photoLink: ownerPermission.photoLink, role: "Owner", isOwner: true, permissionId: nil)
                            }
                            
                            // Other users
                            ForEach(permissions.filter { $0.role != "owner" && $0.type == "user" }, id: \.id) { perm in
                                userRow(
                                    name: perm.displayName ?? perm.emailAddress ?? "Shared User",
                                    email: perm.emailAddress ?? "",
                                    photoLink: perm.photoLink,
                                    role: roleDisplayName(perm.role),
                                    isOwner: false,
                                    permissionId: perm.id
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Divider()
                            .background(Color(white: 0.2))
                            .padding(.horizontal, 20)
                        
                        // General Access Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("General access")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            HStack(alignment: .top, spacing: 12) {
                                // Icon
                                ZStack {
                                    Circle()
                                        .fill(localIsPublic ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: localIsPublic ? "globe" : "lock")
                                        .font(.system(size: 14))
                                        .foregroundColor(localIsPublic ? .green : .gray)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Picker("", selection: Binding(
                                            get: { localIsPublic ? "public" : "private" },
                                            set: { newValue in
                                                let targetPublic = (newValue == "public")
                                                localIsPublic = targetPublic
                                                handleGeneralAccessTypeChange(isPublic: targetPublic, role: localGeneralRole)
                                            }
                                        )) {
                                            Text("Restricted").tag("private")
                                            Text("Anyone with the link").tag("public")
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .tint(.white)
                                        
                                        if localIsPublic {
                                            Picker("", selection: Binding(
                                                get: { localGeneralRole },
                                                set: { newRole in
                                                    localGeneralRole = newRole
                                                    handleGeneralAccessTypeChange(isPublic: true, role: newRole)
                                                }
                                            )) {
                                                Text("Viewer").tag("reader")
                                                Text("Commenter").tag("commenter")
                                                Text("Editor").tag("writer")
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .tint(.gray)
                                        }
                                    }
                                    
                                    Text(localIsPublic ? "Anyone on the internet with the link can view" : "Only people with access can open with the link")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // Footer
            HStack {
                Button(action: handleCopyLink) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Copy link")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color(white: 0.2))
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)
                        .background(Color.blue)
                        .cornerRadius(18)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(white: 0.08))
        }
    }

    // Settings View (matching the screenshot)
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Back Arrow
            HStack(spacing: 16) {
                Button(action: {
                    isShowingSettings = false
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Text("Settings for \"\(item.displayName)\"")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 20) {
                // Status message for settings view
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                Text("Access")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                
                // Checkbox 1
                HStack(alignment: .top, spacing: 14) {
                    GDriveCheckbox(isChecked: writersCanShare) {
                        toggleWritersCanShare()
                    }
                    .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow editors to change permissions and share")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Button(action: {
                            if let url = URL(string: "https://support.google.com/drive/answer/2494822") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Learn more about editors sharing settings")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Checkbox 2
                HStack(alignment: .top, spacing: 14) {
                    GDriveCheckbox(isChecked: limitAccess) {
                        toggleLimitAccess()
                    }
                    .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Limit access to \"\(item.displayName)\"")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        (
                            Text("Some people may lose access. Only the owner and people added directly to this folder can open it. Its name and icon will still be visible in parent folder. ")
                                .foregroundColor(.gray)
                            +
                            Text("Learn more")
                                .foregroundColor(.blue)
                                .underline()
                        )
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .onTapGesture {
                            if let url = URL(string: "https://support.google.com/drive/answer/2494822") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(.bottom, 20)
        .background(Color(red: 0.094, green: 0.098, blue: 0.102)) // #18191A
    }
    
    // User Row View Builder
    @ViewBuilder
    private func userRow(name: String, email: String, photoLink: String?, role: String, isOwner: Bool, permissionId: String?) -> some View {
        HStack(spacing: 12) {
            if let photoLink = photoLink, let url = URL(string: photoLink) {
                AsyncImage(url: url) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsAvatar(name: name)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                initialsAvatar(name: name)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if isOwner {
                Text(role)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else if let permId = permissionId {
                Menu {
                    Button("Viewer") { updatePermissionRole(permId: permId, newRole: "reader") }
                    Button("Commenter") { updatePermissionRole(permId: permId, newRole: "commenter") }
                    Button("Editor") { updatePermissionRole(permId: permId, newRole: "writer") }
                    Divider()
                    Button("Remove access", role: .destructive) { deletePermission(permId: permId) }
                } label: {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90, alignment: .trailing)
            }
        }
    }
    
    private func initialsAvatar(name: String) -> some View {
        let initials = name.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
        return ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 32, height: 32)
            
            Text(initials.prefix(2).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private func roleDisplayName(_ role: String) -> String {
        switch role {
        case "reader": return "Viewer"
        case "commenter": return "Commenter"
        case "writer": return "Editor"
        case "owner": return "Owner"
        default: return role.capitalized
        }
    }
    
    // API logic calls
    private func loadData(showSpinner: Bool = true) async {
        if showSpinner {
            isLoading = true
        }
        errorMessage = nil
        do {
            async let permissionsResult = NotchGoogleDriveService.shared.fetchPermissions(fileId: fileId, portalBaseURL: portalBaseURL)
            async let userResult = NotchGoogleDriveService.shared.fetchUserInfo(portalBaseURL: portalBaseURL)
            async let settingsResult = NotchGoogleDriveService.shared.fetchFileSettings(fileId: fileId, portalBaseURL: portalBaseURL)
            
            let fetchedPermissions = try await permissionsResult
            let fetchedUser = try await userResult
            let fetchedSettings = try await settingsResult
            
            await MainActor.run {
                self.permissions = fetchedPermissions
                self.currentUser = fetchedUser
                self.writersCanShare = fetchedSettings
                
                // Sync local states
                let anyonePerm = fetchedPermissions.first(where: { $0.type == "anyone" })
                self.localIsPublic = anyonePerm != nil
                self.localGeneralRole = anyonePerm?.role ?? "reader"
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load permissions: \(error.localizedDescription)"
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
    
    private func handleAddPermission() {
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        errorMessage = nil
        
        let originalPermissions = self.permissions
        
        // Optimistically add a temporary permission object
        let tempId = "temp-\(UUID().uuidString)"
        let tempPerm = GoogleDrivePermission(
            id: tempId,
            emailAddress: email,
            role: newRole,
            displayName: email.components(separatedBy: "@").first ?? email,
            photoLink: nil,
            type: "user"
        )
        self.permissions.append(tempPerm)
        let addedEmail = email
        newEmail = ""
        
        Task {
            do {
                try await NotchGoogleDriveService.shared.addPermission(fileId: fileId, email: addedEmail, role: newRole, portalBaseURL: portalBaseURL)
                await MainActor.run {
                    showToast("Successfully shared with \(addedEmail)")
                }
                await loadData(showSpinner: false)
            } catch {
                await MainActor.run {
                    // Rollback
                    self.permissions = originalPermissions
                    self.newEmail = addedEmail
                    errorMessage = "Failed to share: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func updatePermissionRole(permId: String, newRole: String) {
        errorMessage = nil
        let originalPermissions = self.permissions
        
        // Optimistically update role
        if let idx = self.permissions.firstIndex(where: { $0.id == permId }) {
            self.permissions[idx].role = newRole
        }
        
        Task {
            do {
                try await NotchGoogleDriveService.shared.updatePermission(fileId: fileId, permissionId: permId, role: newRole, portalBaseURL: portalBaseURL)
                await MainActor.run {
                    showToast("Role updated successfully.")
                }
                await loadData(showSpinner: false)
            } catch {
                await MainActor.run {
                    // Rollback
                    self.permissions = originalPermissions
                    errorMessage = "Failed to update role: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deletePermission(permId: String) {
        errorMessage = nil
        let originalPermissions = self.permissions
        
        // Optimistically remove permission
        self.permissions.removeAll(where: { $0.id == permId })
        
        Task {
            do {
                try await NotchGoogleDriveService.shared.deletePermission(fileId: fileId, permissionId: permId, portalBaseURL: portalBaseURL)
                await MainActor.run {
                    showToast("Access removed successfully.")
                }
                await loadData(showSpinner: false)
            } catch {
                await MainActor.run {
                    // Rollback
                    self.permissions = originalPermissions
                    errorMessage = "Failed to remove access: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleGeneralAccessTypeChange(isPublic: Bool, role: String) {
        errorMessage = nil
        
        Task {
            do {
                try await NotchGoogleDriveService.shared.updateGeneralAccess(fileId: fileId, isPublic: isPublic, role: role, portalBaseURL: portalBaseURL)
                await MainActor.run {
                    showToast("General access updated.")
                }
                await loadData(showSpinner: false)
            } catch {
                await MainActor.run {
                    // Rollback local states on error
                    let anyonePerm = self.permissions.first(where: { $0.type == "anyone" })
                    self.localIsPublic = anyonePerm != nil
                    self.localGeneralRole = anyonePerm?.role ?? "reader"
                    
                    errorMessage = "Failed to update general access: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleCopyLink() {
        let link = "https://drive.google.com/file/d/\(fileId)/view?usp=drivesdk"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSString])
        showToast("Copied link to clipboard!")
    }

    private func toggleWritersCanShare() {
        let newValue = !writersCanShare
        writersCanShare = newValue
        errorMessage = nil
        statusMessage = "Updating sharing settings..."
        
        Task {
            do {
                try await NotchGoogleDriveService.shared.updateFileSettings(fileId: fileId, writersCanShare: newValue, portalBaseURL: portalBaseURL)
                await MainActor.run {
                    statusMessage = nil
                    showToast("Sharing settings updated.")
                }
            } catch {
                await MainActor.run {
                    writersCanShare = !newValue // Rollback
                    statusMessage = nil
                    errorMessage = "Failed to update sharing settings: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func toggleLimitAccess() {
        limitAccess.toggle()
        showToast("Folder access restrictions updated.")
    }
}
