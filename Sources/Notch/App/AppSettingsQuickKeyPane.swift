import SwiftUI

/// Settings → Shortcuts: remap spare keys to app shortcuts (QuickKey).
struct AppQuickKeySettingsPane: View {
    @ObservedObject private var store = QuickKeyStore.shared
    @ObservedObject private var accessibility = QuickKeyAccessibility.shared
    @ObservedObject var presentationModel: NotchPresentationModel
    @AppStorage("app_language") private var appLanguage: String = "English"

    @State private var editing: QuickKeyMapping?
    @State private var isAdding = false

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Shortcuts", lang: appLanguage),
                subtitle: Localization.get("Map spare keys to any app shortcut", lang: appLanguage)
            )

            if !accessibility.isTrusted {
                AppSettingsCard(title: Localization.get("Permission", lang: appLanguage)) {
                    AppSettingsRow(showDivider: false) {
                        rowIcon("lock.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Localization.get("Accessibility required", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(Localization.get("Needed to read and send key events", lang: appLanguage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        StandardActionButton(
                            title: Localization.get("Open Settings", lang: appLanguage),
                            tint: tint,
                            variant: .secondary,
                            action: { accessibility.openSystemSettings() }
                        )
                        StandardActionButton(
                            title: Localization.get("Grant", lang: appLanguage),
                            tint: tint,
                            variant: .primary,
                            action: { accessibility.request() }
                        )
                    }
                }
            }

            AppSettingsCard(title: Localization.get("Engine", lang: appLanguage)) {
                AppSettingsRow(showDivider: false) {
                    rowIcon("keyboard.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.get("Enable remapper", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("\(store.enabledCount) \(Localization.get("active", lang: appLanguage))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: $store.isEngineEnabled)
                        .toggleStyle(NotchSwitchStyle(tint: tint))
                        .labelsHidden()
                }
            }

            AppSettingsCard(
                title: Localization.get("Keybindings", lang: appLanguage),
                subtitle: Localization.get("Key → Send", lang: appLanguage)
            ) {
                if store.mappings.isEmpty {
                    AppSettingsRow(showDivider: false) {
                        Text(Localization.get("No shortcuts yet", lang: appLanguage))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        StandardActionButton(
                            title: Localization.get("Add", lang: appLanguage),
                            icon: "plus",
                            tint: tint,
                            variant: .primary,
                            action: { isAdding = true }
                        )
                    }
                } else {
                    ForEach(Array(store.mappings.enumerated()), id: \.element.id) { index, mapping in
                        mappingRow(mapping, showDivider: index < store.mappings.count - 1)
                    }

                    AppSettingsRow(showDivider: false) {
                        Spacer()
                        StandardActionButton(
                            title: Localization.get("Add shortcut", lang: appLanguage),
                            icon: "plus",
                            tint: tint,
                            variant: .secondary,
                            action: { isAdding = true }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            QuickKeyEditorSheet(existing: nil, tint: tint) { store.add($0) }
        }
        .sheet(item: $editing) { mapping in
            QuickKeyEditorSheet(existing: mapping, tint: tint) { store.update($0) }
        }
        .onAppear {
            accessibility.refreshAndSyncEngine()
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.1).cornerRadius(8))
    }

    private func mappingRow(_ mapping: QuickKeyMapping, showDivider: Bool) -> some View {
        AppSettingsRow(showDivider: showDivider) {
            rowIcon(mapping.isEnabled ? "keyboard" : "keyboard.chevron.compact.down")

            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(mapping.isEnabled ? 0.9 : 0.45))
                Text(mapping.whenDisplay)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 8)

            chordBadge(mapping.triggerDisplay)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
            chordBadge(mapping.targetDisplay)

            StandardActionButton(
                title: Localization.get("Edit", lang: appLanguage),
                tint: tint,
                variant: .secondary,
                action: { editing = mapping }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = mapping }
        .contextMenu {
            Button(Localization.get("Edit", lang: appLanguage)) { editing = mapping }
            Button(mapping.isEnabled
                   ? Localization.get("Disable", lang: appLanguage)
                   : Localization.get("Enable", lang: appLanguage)) {
                store.toggle(mapping)
            }
            Divider()
            Button(Localization.get("Delete", lang: appLanguage), role: .destructive) {
                store.delete(mapping)
            }
        }
        .opacity(mapping.isEnabled ? 1 : 0.7)
    }

    private func chordBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
