import NotchShelfFeature
import SwiftUI

struct AppShelfSettingsPane: View {
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject private var preferences: NotchShelfPreferences
    @AppStorage("app_language") private var appLanguage: String = "English"

    init(shelf: NotchShelfViewModel, presentationModel: NotchPresentationModel) {
        self.shelf = shelf
        self.presentationModel = presentationModel
        _preferences = ObservedObject(wrappedValue: shelf.preferences)
    }

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Shelf", lang: appLanguage),
                subtitle: Localization.get("Manage how dropped items appear, sync, and expire.", lang: appLanguage)
            )

            googleDriveCard
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

            pickerRow(
                icon: "doc.on.doc.fill",
                title: Localization.get("Automatically Upload", lang: appLanguage),
                options: NotchShelfAutoUploadScope.allCases,
                selection: Binding(
                    get: { preferences.autoUploadScope },
                    set: { preferences.autoUploadScope = $0 }
                ),
                titleMapper: autoUploadScopeTitle,
                showDivider: false
            )
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.1).cornerRadius(8))
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

    private func autoUploadScopeTitle(_ value: NotchShelfAutoUploadScope) -> String {
        Localization.get(value == .filesOnly ? "Files Only" : "All Items", lang: appLanguage)
    }
}
