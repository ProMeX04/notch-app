import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppShortcutsSettingsPane: View {
    @ObservedObject var shortcutStore: ShortcutStore
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    @State private var isAddingNew = false
    @State private var editingItem: ShortcutItem?
    @State private var draftName: String = ""
    @State private var draftImagePath: String?
    @State private var draftTintColor: String = "blue"
    @State private var draftActionType: ShortcutActionType = .openURL
    @State private var draftURLText: String = ""
    @State private var draftBundleIDText: String = ""
    @State private var draftScriptText: String = ""
    @State private var draftShellText: String = ""
    @State private var isShowingAppPicker = false
    @State private var appPickerQuery = ""

    private var tint: Color {
        settingsAccentColor(from: accentColorID)
    }

    private enum ShortcutActionType: String, CaseIterable, Identifiable {
        case openURL = "Open URL"
        case launchApp = "Launch App"
        case appleScript = "AppleScript"
        case shellCommand = "Shell Command"

        var id: String { rawValue }
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Shortcuts", lang: appLanguage),
                subtitle: "Create custom shortcuts to open apps, URLs, run scripts, and more from the notch."
            )

            if shortcutStore.items.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shortcutStore.items) { item in
                        shortcutRow(item)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
            }

            addBarButton
        }
        .sheet(isPresented: $isAddingNew) {
            editSheet
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "command")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(tint.opacity(0.5))

            Text("No shortcuts yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                startAdding()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add Shortcut")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(tint.ensureMinimumBrightness(factor: 0.78))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Shortcut Row

    @ViewBuilder
    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(spacing: 12) {
            ShortcutArtworkView(
                item: item,
                size: 32,
                cornerRadius: 8,
                tint: colorForName(item.tintColor)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(item.action.typeName + " — " + item.action.previewText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button {
                startEditing(item)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                shortcutStore.delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .sheet(isPresented: Binding(
            get: { editingItem?.id == item.id },
            set: { if !$0 { editingItem = nil } }
        )) {
            editSheet
        }

        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    // MARK: - Add Bar Button

    private var addBarButton: some View {
        HStack {
            Spacer()
            Button {
                startAdding()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add Shortcut")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(tint.ensureMinimumBrightness(factor: 0.72))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.1))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 14)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        VStack(spacing: 16) {
            Text(editingItem == nil ? "New Shortcut" : "Edit Shortcut")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            // Action type
            HStack(spacing: 8) {
                Text("Action")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 58, alignment: .trailing)
                NotchSegmentedPicker(
                    options: ShortcutActionType.allCases,
                    selection: $draftActionType,
                    titleMapper: { $0.rawValue },
                    tint: tint
                )
            }

            // Action input
            actionInputField

            // Name
            HStack(spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 58, alignment: .trailing)
                TextField(namePlaceholder, text: $draftName)
                    .textFieldStyle(.roundedBorder)
            }

            if showsCustomArtworkControls {
                HStack(spacing: 8) {
                    Text("Image")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 58, alignment: .trailing)
                    Button {
                        chooseDraftImage()
                    } label: {
                        HStack(spacing: 8) {
                            if draftImagePath != nil {
                                ShortcutArtworkView(
                                    item: draftPreviewItem,
                                    size: 28,
                                    cornerRadius: 7,
                                    tint: tint
                                )
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(tint.opacity(0.12))
                                    Image(systemName: effectiveDraftIcon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(tint.ensureMinimumBrightness(factor: 0.72))
                                }
                                .frame(width: 28, height: 28)
                            }

                            Text(imageSelectionLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(draftImagePath == nil ? .white.opacity(0.35) : .white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("Browse")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint.ensureMinimumBrightness(factor: 0.72))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if draftImagePath != nil {
                        Button {
                            draftImagePath = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Remove image")
                    }
                }

                HStack(spacing: 8) {
                    Text("Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 58, alignment: .trailing)
                    HStack(spacing: 6) {
                        ForEach(colorOptions, id: \.self) { colorName in
                            Button {
                                draftTintColor = colorName
                            } label: {
                                Circle()
                                    .fill(colorForName(colorName))
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if draftTintColor == colorName {
                                            Circle().stroke(.white, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Buttons
            HStack {
                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Button(editingItem == nil ? "Add" : "Save") {
                    saveDraft()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(tint.ensureMinimumBrightness(factor: 0.78))
                )
                .disabled(!isDraftValid)
                .opacity(isDraftValid ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(width: 480, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    // MARK: - Action Input

    @ViewBuilder
    private var actionInputField: some View {
        switch draftActionType {
        case .openURL:
            HStack(spacing: 8) {
                Text("URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 58, alignment: .trailing)
                TextField("https://example.com", text: $draftURLText)
                    .textFieldStyle(.roundedBorder)
            }
        case .launchApp:
            HStack(spacing: 8) {
                Text("App")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 58, alignment: .trailing)
                Button {
                    appPickerQuery = ""
                    isShowingAppPicker = true
                } label: {
                    HStack(spacing: 8) {
                        if let app = InstalledApp.fromBundleID(draftBundleIDText) {
                            app.iconView(size: 22)
                            Text(app.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        } else if !draftBundleIDText.isEmpty {
                            Image(systemName: "app")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(draftBundleIDText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Choose an app…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Spacer()
                        Text("Choose")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint.ensureMinimumBrightness(factor: 0.72))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isShowingAppPicker) {
                    appPickerSheet
                }
            }
        case .appleScript:
            VStack(alignment: .leading, spacing: 4) {
                Text("AppleScript Source")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 66)
                HStack(spacing: 8) {
                    Spacer().frame(width: 58)
                    TextEditor(text: $draftScriptText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }
        case .shellCommand:
            VStack(alignment: .leading, spacing: 4) {
                Text("Shell Command")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 66)
                HStack(spacing: 8) {
                    Spacer().frame(width: 58)
                    TextEditor(text: $draftShellText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }
        }
    }

    // MARK: - Editing Logic

    private var isDraftValid: Bool {
        switch draftActionType {
        case .openURL:
            return !draftName.trimmingCharacters(in: .whitespaces).isEmpty &&
                !draftURLText.trimmingCharacters(in: .whitespaces).isEmpty
        case .launchApp:
            return !draftBundleIDText.trimmingCharacters(in: .whitespaces).isEmpty
        case .appleScript:
            return !draftName.trimmingCharacters(in: .whitespaces).isEmpty &&
                !draftScriptText.trimmingCharacters(in: .whitespaces).isEmpty
        case .shellCommand:
            return !draftName.trimmingCharacters(in: .whitespaces).isEmpty &&
                !draftShellText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func startAdding() {
        editingItem = nil
        resetDrafts()
        isAddingNew = true
    }

    private func startEditing(_ item: ShortcutItem) {
        editingItem = item
        draftName = item.name
        draftImagePath = item.imagePath
        draftTintColor = item.tintColor
        switch item.action {
        case .openURL(let url):
            draftActionType = .openURL
            draftURLText = url
        case .launchApp(let bundleID):
            draftActionType = .launchApp
            draftBundleIDText = bundleID
        case .appleScript(let source):
            draftActionType = .appleScript
            draftScriptText = source
        case .shellCommand(let cmd):
            draftActionType = .shellCommand
            draftShellText = cmd
        case .plugin:
            draftActionType = .openURL
        }
    }

    private func cancelEditing() {
        editingItem = nil
        isAddingNew = false
        resetDrafts()
    }

    private func saveDraft() {
        let action: ShortcutAction
        switch draftActionType {
        case .openURL: action = .openURL(draftURLText.trimmingCharacters(in: .whitespaces))
        case .launchApp: action = .launchApp(bundleID: draftBundleIDText.trimmingCharacters(in: .whitespaces))
        case .appleScript: action = .appleScript(source: draftScriptText)
        case .shellCommand: action = .shellCommand(draftShellText.trimmingCharacters(in: .whitespaces))
        }

        if let existing = editingItem {
            var updated = existing
            updated.name = resolvedDraftName
            updated.icon = effectiveDraftIcon
            updated.imagePath = effectiveDraftImagePath
            updated.tintColor = draftTintColor
            updated.action = action
            shortcutStore.update(updated)
        } else {
            let item = ShortcutItem(
                name: resolvedDraftName,
                icon: effectiveDraftIcon,
                imagePath: effectiveDraftImagePath,
                tintColor: draftTintColor,
                action: action
            )
            shortcutStore.add(item)
        }
        editingItem = nil
        isAddingNew = false
        resetDrafts()
    }

    private func resetDrafts() {
        draftName = ""
        draftImagePath = nil
        draftTintColor = "blue"
        draftActionType = .openURL
        draftURLText = ""
        draftBundleIDText = ""
        draftScriptText = ""
        draftShellText = ""
    }

    private var normalizedDraftImagePath: String? {
        guard let draftImagePath else { return nil }
        let trimmed = draftImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var showsCustomArtworkControls: Bool {
        draftActionType != .launchApp
    }

    private var namePlaceholder: String {
        if draftActionType == .launchApp {
            return "Optional - defaults to app name"
        }
        return "Shortcut name"
    }

    private var resolvedDraftName: String {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if draftActionType == .launchApp,
           let app = InstalledApp.fromBundleID(draftBundleIDText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return app.name
        }

        return trimmedName
    }

    private var imageSelectionLabel: String {
        guard let path = normalizedDraftImagePath else { return "Optional - use image instead of default icon" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var draftPreviewAction: ShortcutAction {
        switch draftActionType {
        case .openURL:
            return .openURL(draftURLText.trimmingCharacters(in: .whitespaces))
        case .launchApp:
            return .launchApp(bundleID: draftBundleIDText.trimmingCharacters(in: .whitespaces))
        case .appleScript:
            return .appleScript(source: draftScriptText)
        case .shellCommand:
            return .shellCommand(draftShellText.trimmingCharacters(in: .whitespaces))
        }
    }

    private var draftPreviewItem: ShortcutItem {
        ShortcutItem(
            name: draftName.isEmpty ? "Preview" : draftName,
            icon: effectiveDraftIcon,
            imagePath: effectiveDraftImagePath,
            tintColor: draftTintColor,
            action: draftPreviewAction
        )
    }

    private var effectiveDraftIcon: String {
        switch draftActionType {
        case .openURL:
            return "globe"
        case .launchApp:
            return "app"
        case .appleScript:
            return "applescript"
        case .shellCommand:
            return "terminal"
        }
    }

    private var effectiveDraftImagePath: String? {
        draftActionType == .launchApp ? nil : normalizedDraftImagePath
    }

    private func chooseDraftImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        draftImagePath = url.path
    }

    // MARK: - Constants

    private let colorOptions = [
        "blue", "purple", "orange", "green", "red",
        "yellow", "pink", "teal", "indigo", "mint"
    ]

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return Color(nsColor: .systemBlue)
        case "purple": return Color(nsColor: .systemPurple)
        case "orange": return Color(nsColor: .systemOrange)
        case "green": return Color(nsColor: .systemGreen)
        case "red": return Color(nsColor: .systemRed)
        case "yellow": return Color(nsColor: .systemYellow)
        case "pink": return Color(nsColor: .systemPink)
        case "teal": return Color(nsColor: .systemTeal)
        case "indigo": return Color(nsColor: .systemIndigo)
        case "mint": return Color(nsColor: .systemMint)
        default: return Color(nsColor: .systemBlue)
        }
    }
}

// MARK: - Installed App

private struct InstalledApp: Identifiable {
    let name: String
    let bundleID: String
    let url: URL
    let icon: NSImage?

    var id: String { bundleID }

    @ViewBuilder
    func iconView(size: CGFloat) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "app")
                .font(.system(size: size * 0.6, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: size, height: size)
        }
    }

    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let searchPaths = ["/Applications", "/System/Applications"]
        var results: [InstalledApp] = []

        for searchPath in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: searchPath), includingPropertiesForKeys: nil) else { continue }
            for itemURL in contents {
                guard itemURL.pathExtension == "app" else { continue }
                let plistURL = itemURL.appendingPathComponent("Contents/Info.plist")
                guard let plistData = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                      let bundleID = plist["CFBundleIdentifier"] as? String,
                      let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) else { continue }

                let icon = NSWorkspace.shared.icon(forFile: itemURL.path)
                results.append(InstalledApp(name: name, bundleID: bundleID, url: itemURL, icon: icon))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @MainActor private static var cachedApps: [InstalledApp]?
    @MainActor static func allApps() -> [InstalledApp] {
        if let cached = cachedApps { return cached }
        let apps = scan()
        cachedApps = apps
        return apps
    }

    @MainActor static func fromBundleID(_ bundleID: String) -> InstalledApp? {
        allApps().first { $0.bundleID == bundleID }
    }
}

// MARK: - App Picker Extension

extension AppShortcutsSettingsPane {
    private var appPickerSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose App")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Cancel") {
                    isShowingAppPicker = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
            }

            TextField("Search apps…", text: $appPickerQuery)
                .textFieldStyle(.roundedBorder)

            let filtered = appPickerQuery.isEmpty
                ? InstalledApp.allApps()
                : InstalledApp.allApps().filter {
                    $0.name.localizedCaseInsensitiveContains(appPickerQuery) ||
                    $0.bundleID.localizedCaseInsensitiveContains(appPickerQuery)
                }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { app in
                        Button {
                            draftBundleIDText = app.bundleID
                            isShowingAppPicker = false
                        } label: {
                            HStack(spacing: 10) {
                                app.iconView(size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.88))
                                    Text(app.bundleID)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                Spacer()
                                if app.bundleID == draftBundleIDText {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(tint.ensureMinimumBrightness(factor: 0.72))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 1)
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 440, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}
