import NotchShelfCore
import SwiftUI

struct AppShelfSettingsPane: View {
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject private var preferences: NotchShelfPreferences
    @AppStorage("app_language") private var appLanguage: String = "English"

    @State private var pendingRetentionPolicy: NotchShelfRetentionPolicy?
    @State private var pendingRetentionPreview: NotchShelfCleanupPreview?
    @State private var showRetentionConfirmation = false
    @State private var showDriveCleanupWarning = false
    @State private var showClearSheet = false
    @State private var showCloudClearConfirmation = false
    @State private var deleteDriveFilesOnClear = false
    @State private var showDestructiveDriveCleanupConfirm = false
    @State private var pendingDriveCleanupPreview: NotchShelfCleanupPreview?

    init(shelf: NotchShelfViewModel, presentationModel: NotchPresentationModel) {
        self.shelf = shelf
        self.presentationModel = presentationModel
        _preferences = ObservedObject(wrappedValue: shelf.preferences)
    }

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    private var uploadedItemCount: Int {
        shelf.items.filter { $0.driveFileID != nil }.count
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Shelf", lang: appLanguage),
                subtitle: Localization.get("Manage how dropped items appear, sync, and expire.", lang: appLanguage)
            )

            appearanceCard
            behaviorCard
            googleDriveCard
            storageCard
        }
        .alert(
            Localization.get("Apply Retention Policy?", lang: appLanguage),
            isPresented: $showRetentionConfirmation
        ) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {
                pendingRetentionPolicy = nil
                pendingRetentionPreview = nil
            }
            Button(Localization.get("Apply", lang: appLanguage), role: .destructive) {
                if let pendingRetentionPolicy {
                    shelf.applyRetentionPolicy(pendingRetentionPolicy)
                }
                self.pendingRetentionPolicy = nil
                pendingRetentionPreview = nil
            }
        } message: {
            Text(retentionConfirmationMessage)
        }
        .alert(
            Localization.get("Delete Drive Files Automatically?", lang: appLanguage),
            isPresented: $showDriveCleanupWarning
        ) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {}
            Button(Localization.get("Enable", lang: appLanguage), role: .destructive) {
                preferences.deleteDriveFilesDuringAutomaticCleanup = true
                shelf.applyRetentionPolicy(preferences.retentionPolicy)
            }
        } message: {
            Text(Localization.get("Expired or excess Shelf items that were uploaded will also be deleted from Google Drive. This cannot be undone.", lang: appLanguage))
        }
        .alert(
            Localization.get("Delete Uploaded Files from Google Drive?", lang: appLanguage),
            isPresented: $showDestructiveDriveCleanupConfirm
        ) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {
                pendingDriveCleanupPreview = nil
            }
            Button(Localization.get("Delete Files and Enable", lang: appLanguage), role: .destructive) {
                preferences.deleteDriveFilesDuringAutomaticCleanup = true
                shelf.applyRetentionPolicy(preferences.retentionPolicy)
                pendingDriveCleanupPreview = nil
            }
        } message: {
            if let preview = pendingDriveCleanupPreview {
                Text(String(
                    format: Localization.get("This will immediately remove %d items from Shelf and delete %d files from Google Drive. This cannot be undone.", lang: appLanguage),
                    preview.itemsToRemoveCount,
                    preview.driveItemsToDeleteCount
                ))
            }
        }
        .sheet(isPresented: $showClearSheet) {
            clearShelfSheet
        }
        .alert(
            Localization.get("Delete Google Drive Files?", lang: appLanguage),
            isPresented: $showCloudClearConfirmation
        ) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {
                deleteDriveFilesOnClear = false
            }
            Button(Localization.get("Delete Files and Clear Shelf", lang: appLanguage), role: .destructive) {
                shelf.clearShelf(deleteDriveFiles: true)
                deleteDriveFilesOnClear = false
            }
        } message: {
            Text(String(
                format: Localization.get("%d uploaded items will be deleted from Google Drive. This cannot be undone.", lang: appLanguage),
                uploadedItemCount
            ))
        }
    }

    private var appearanceCard: some View {
        AppSettingsCard(title: Localization.get("Appearance", lang: appLanguage)) {
            pickerRow(
                icon: "square.grid.3x3.fill",
                title: Localization.get("Item Size", lang: appLanguage),
                options: NotchShelfItemSize.allCases,
                selection: Binding(
                    get: { preferences.itemSize },
                    set: { preferences.itemSize = $0 }
                ),
                titleMapper: itemSizeTitle
            )

            toggleRow(
                icon: "textformat",
                title: Localization.get("Show Item Names", lang: appLanguage),
                isOn: Binding(
                    get: { preferences.showItemNames },
                    set: { preferences.showItemNames = $0 }
                ),
                showDivider: true
            )

            toggleRow(
                icon: "checkmark.icloud.fill",
                title: Localization.get("Show Google Drive Status Badges", lang: appLanguage),
                isOn: Binding(
                    get: { preferences.showDriveBadges },
                    set: { preferences.showDriveBadges = $0 }
                ),
                showDivider: false
            )
        }
    }

    private var behaviorCard: some View {
        AppSettingsCard(title: Localization.get("Behavior", lang: appLanguage)) {
            pickerRow(
                icon: "arrow.up.to.line",
                title: Localization.get("When Dropping Existing Items", lang: appLanguage),
                options: NotchShelfDuplicateDropAction.allCases,
                selection: Binding(
                    get: { preferences.duplicateDropAction },
                    set: { preferences.duplicateDropAction = $0 }
                ),
                titleMapper: duplicateTitle
            )

            pickerRow(
                icon: "link",
                title: Localization.get("Double-click Links", lang: appLanguage),
                options: NotchShelfLinkDoubleClickAction.allCases,
                selection: Binding(
                    get: { preferences.linkDoubleClickAction },
                    set: { preferences.linkDoubleClickAction = $0 }
                ),
                titleMapper: linkDoubleClickTitle,
                showDivider: false
            )
        }
    }

    private var googleDriveCard: some View {
        AppSettingsCard(title: "Google Drive") {
            AppSettingsRow(showDivider: true) {
                rowIcon("externaldrive.connected.to.line.below.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(Localization.get("Connection", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(Localization.get(shelf.isGoogleDriveConnected ? "Connected" : "Not Connected", lang: appLanguage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(shelf.isGoogleDriveConnected ? tint : .white.opacity(0.48))
                }
                Spacer()
                StandardActionButton(
                    title: Localization.get(shelf.isGoogleDriveConnected ? "Disconnect" : "Connect", lang: appLanguage),
                    tint: tint,
                    variant: shelf.isGoogleDriveConnected ? .secondary : .primary,
                    action: {
                        if shelf.isGoogleDriveConnected {
                            shelf.disconnectGoogleDrive()
                        } else {
                            shelf.connectGoogleDrive()
                        }
                    }
                )
            }

            toggleRow(
                icon: "icloud.and.arrow.up.fill",
                title: Localization.get("Auto-upload New Items", lang: appLanguage),
                isOn: Binding(
                    get: { preferences.autoUploadEnabled },
                    set: { preferences.autoUploadEnabled = $0 }
                ),
                showDivider: true
            )

            pickerRow(
                icon: "doc.on.doc.fill",
                title: Localization.get("Automatically Upload", lang: appLanguage),
                options: NotchShelfAutoUploadScope.allCases,
                selection: Binding(
                    get: { preferences.autoUploadScope },
                    set: { preferences.autoUploadScope = $0 }
                ),
                titleMapper: autoUploadScopeTitle,
                disabled: !preferences.autoUploadEnabled,
                showDivider: false
            )
        }
    }

    private var storageCard: some View {
        AppSettingsCard(title: Localization.get("Storage & Cleanup", lang: appLanguage)) {
            widePickerRow(
                icon: "number.square.fill",
                title: Localization.get("Maximum Items", lang: appLanguage),
                options: NotchShelfMaximumItemCount.allCases,
                selection: Binding(
                    get: { preferences.maximumItemCount },
                    set: { proposeRetention(maximum: $0, expiration: preferences.expirationInterval) }
                ),
                titleMapper: maximumCountTitle
            )

            widePickerRow(
                icon: "clock.badge.xmark.fill",
                title: Localization.get("Remove Items Older Than", lang: appLanguage),
                options: NotchShelfExpirationInterval.allCases,
                selection: Binding(
                    get: { preferences.expirationInterval },
                    set: { proposeRetention(maximum: preferences.maximumItemCount, expiration: $0) }
                ),
                titleMapper: expirationTitle
            )

            toggleRow(
                icon: "icloud.slash.fill",
                title: Localization.get("Delete Uploaded Google Drive Files During Automatic Cleanup", lang: appLanguage),
                isOn: Binding(
                    get: { preferences.deleteDriveFilesDuringAutomaticCleanup },
                    set: { value in
                        if value {
                            let preview = shelf.previewRetentionPolicy(preferences.retentionPolicy)
                            if preview.driveItemsToDeleteCount > 0 {
                                pendingDriveCleanupPreview = preview
                                showDestructiveDriveCleanupConfirm = true
                            } else {
                                showDriveCleanupWarning = true
                            }
                        } else {
                            preferences.deleteDriveFilesDuringAutomaticCleanup = false
                        }
                    }
                ),
                showDivider: true
            )

            AppSettingsRow(showDivider: false) {
                rowIcon("trash.square.fill")
                Text(String(
                    format: Localization.get("%d items stored on Shelf", lang: appLanguage),
                    shelf.items.count
                ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                Spacer()
                StandardActionButton(
                    title: Localization.get("Clear Shelf", lang: appLanguage),
                    tint: .red,
                    variant: .secondary,
                    action: {
                        deleteDriveFilesOnClear = false
                        showClearSheet = true
                    }
                )
            }
        }
    }

    private var clearShelfSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Localization.get("Clear Shelf?", lang: appLanguage))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text(String(
                format: Localization.get("Remove all %d items from Shelf? This removes local Shelf references and temporary previews.", lang: appLanguage),
                shelf.items.count
            ))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)

            Toggle(
                Localization.get("Also delete uploaded files from Google Drive", lang: appLanguage),
                isOn: $deleteDriveFilesOnClear
            )
            .toggleStyle(NotchSwitchStyle(tint: .red))
            .foregroundStyle(.white.opacity(0.9))
            .disabled(uploadedItemCount == 0)

            HStack {
                Spacer()
                StandardActionButton(
                    title: Localization.get("Cancel", lang: appLanguage),
                    tint: tint,
                    variant: .secondary,
                    action: { showClearSheet = false }
                )
                StandardActionButton(
                    title: Localization.get("Clear", lang: appLanguage),
                    tint: .red,
                    variant: .primary,
                    action: {
                        showClearSheet = false
                        if deleteDriveFilesOnClear && uploadedItemCount > 0 {
                            showCloudClearConfirmation = true
                        } else {
                            shelf.clearShelf(deleteDriveFiles: false)
                        }
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var retentionConfirmationMessage: String {
        guard let preview = pendingRetentionPreview else { return "" }
        if preferences.deleteDriveFilesDuringAutomaticCleanup && preview.driveItemsToDeleteCount > 0 {
            return String(
                format: Localization.get("This policy removes %d Shelf items and deletes %d uploaded Google Drive files.", lang: appLanguage),
                preview.itemsToRemoveCount,
                preview.driveItemsToDeleteCount
            )
        }
        return String(
            format: Localization.get("This policy removes %d existing Shelf items.", lang: appLanguage),
            preview.itemsToRemoveCount
        )
    }

    private func proposeRetention(maximum: NotchShelfMaximumItemCount, expiration: NotchShelfExpirationInterval) {
        let policy = NotchShelfRetentionPolicy(maximumItemCount: maximum, expirationInterval: expiration)
        let preview = shelf.previewRetentionPolicy(policy)
        if preview.itemsToRemoveCount > 0 {
            pendingRetentionPolicy = policy
            pendingRetentionPreview = preview
            showRetentionConfirmation = true
        } else {
            shelf.applyRetentionPolicy(policy)
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.1).cornerRadius(8))
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>, showDivider: Bool) -> some View {
        AppSettingsRow(showDivider: showDivider) {
            rowIcon(icon)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(NotchSwitchStyle(tint: tint))
                .labelsHidden()
        }
    }

    private func pickerRow<T: Identifiable & Equatable>(
        icon: String,
        title: String,
        options: [T],
        selection: Binding<T>,
        titleMapper: @escaping (T) -> String,
        disabled: Bool = false,
        showDivider: Bool = true
    ) -> some View where T.ID == String {
        AppSettingsRow(showDivider: showDivider) {
            rowIcon(icon)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.45 : 0.9))
            Spacer()
            NotchSegmentedPicker(
                options: options,
                selection: selection,
                titleMapper: titleMapper,
                tint: tint
            )
            .frame(width: options.count > 3 ? 300 : 235)
            .opacity(disabled ? 0.45 : 1)
            .disabled(disabled)
        }
    }

    private func widePickerRow<T: Identifiable & Equatable>(
        icon: String,
        title: String,
        options: [T],
        selection: Binding<T>,
        titleMapper: @escaping (T) -> String,
        showDivider: Bool = true
    ) -> some View where T.ID == String {
        AppSettingsRow(showDivider: showDivider) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    rowIcon(icon)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                NotchSegmentedPicker(
                    options: options,
                    selection: selection,
                    titleMapper: titleMapper,
                    tint: tint
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func itemSizeTitle(_ value: NotchShelfItemSize) -> String {
        Localization.get(value.rawValue.capitalized, lang: appLanguage)
    }

    private func duplicateTitle(_ value: NotchShelfDuplicateDropAction) -> String {
        Localization.get(value == .ignore ? "Ignore" : "Move to Top", lang: appLanguage)
    }

    private func linkDoubleClickTitle(_ value: NotchShelfLinkDoubleClickAction) -> String {
        Localization.get(value == .open ? "Open" : "Copy URL", lang: appLanguage)
    }

    private func autoUploadScopeTitle(_ value: NotchShelfAutoUploadScope) -> String {
        Localization.get(value == .filesOnly ? "Files Only" : "All Items", lang: appLanguage)
    }

    private func maximumCountTitle(_ value: NotchShelfMaximumItemCount) -> String {
        value.value.map(String.init) ?? Localization.get("Unlimited", lang: appLanguage)
    }

    private func expirationTitle(_ value: NotchShelfExpirationInterval) -> String {
        switch value {
        case .never: return Localization.get("Never", lang: appLanguage)
        case .oneDay: return Localization.get("1 Day", lang: appLanguage)
        case .sevenDays: return Localization.get("7 Days", lang: appLanguage)
        case .thirtyDays: return Localization.get("30 Days", lang: appLanguage)
        }
    }
}
