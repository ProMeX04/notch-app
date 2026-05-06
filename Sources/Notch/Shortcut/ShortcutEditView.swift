import SwiftUI

struct ShortcutEditView: View {
    @ObservedObject var viewModel: NotchShortcutViewModel

    @State private var name: String = ""
    @State private var icon: String = "star"
    @State private var imagePath: String?
    @State private var tintColor: String = "blue"
    @State private var actionType: ShortcutActionType = .openURL
    @State private var urlText: String = ""
    @State private var bundleIDText: String = ""
    @State private var scriptText: String = ""
    @State private var shellText: String = ""

    @AppStorage("app_language") private var appLanguage: String = "English"

    private var isEditing: Bool { viewModel.editingItem != nil }

    private enum ShortcutActionType: String, CaseIterable, Identifiable {
        case openURL = "Open URL"
        case launchApp = "Launch App"
        case appleScript = "AppleScript"
        case shellCommand = "Shell Command"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .openURL: return "globe"
            case .launchApp: return "app"
            case .appleScript: return "applescript"
            case .shellCommand: return "terminal"
            }
        }
    }

    init(viewModel: NotchShortcutViewModel) {
        self.viewModel = viewModel
        // Pre-fill if editing existing item
        if let item = viewModel.editingItem {
            _name = State(initialValue: item.name)
            _icon = State(initialValue: item.icon)
            _imagePath = State(initialValue: item.imagePath)
            _tintColor = State(initialValue: item.tintColor)
            switch item.action {
            case .openURL(let url):
                _actionType = State(initialValue: .openURL)
                _urlText = State(initialValue: url)
            case .launchApp(let bundleID):
                _actionType = State(initialValue: .launchApp)
                _bundleIDText = State(initialValue: bundleID)
            case .appleScript(let source):
                _actionType = State(initialValue: .appleScript)
                _scriptText = State(initialValue: source)
            case .shellCommand(let cmd):
                _actionType = State(initialValue: .shellCommand)
                _shellText = State(initialValue: cmd)
            case .plugin:
                _actionType = State(initialValue: .openURL)
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Button {
                    viewModel.finishEditing()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Text(isEditing ? "Edit Shortcut" : "New Shortcut")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }

            // Name
            fieldRow(icon: "character.textbox", label: "Name") {
                TextField("Shortcut name", text: $name)
                    .textFieldStyle(.plain)
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.88))
            }

            // Icon picker
            fieldRow(icon: "square.grid.2x2", label: "Icon") {
                iconPicker
            }

            // Color picker
            fieldRow(icon: "paintpalette", label: "Color") {
                colorPicker
            }

            // Action type
            fieldRow(icon: "bolt", label: "Action") {
                actionTypePicker
            }

            // Action-specific input
            actionInputField

            Spacer(minLength: 0)

            // Save button
            StandardActionButton(
                title: isEditing ? "Save" : "Add",
                icon: "checkmark",
                tint: .blue,
                variant: .primary,
                isDisabled: !isValid
            ) {
                saveItem()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private func fieldRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(NotchPanelFieldMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)
            content()
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                .fill(NotchPanelFieldMetrics.fieldFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                .stroke(NotchPanelFieldMetrics.fieldStroke, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(commonIcons, id: \.self) { iconName in
                        Button {
                            icon = iconName
                        } label: {
                            Image(systemName: iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(icon == iconName ? .black.opacity(0.85) : .white.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(icon == iconName ? Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.78) : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForName(tintColor))
                .frame(width: 14, height: 14)
            Spacer()
            HStack(spacing: 6) {
                ForEach(colorOptions, id: \.self) { colorName in
                    Button {
                        tintColor = colorName
                    } label: {
                        Circle()
                            .fill(colorForName(colorName))
                            .frame(width: 16, height: 16)
                            .overlay {
                                if tintColor == colorName {
                                    Circle()
                                        .stroke(.white, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionTypePicker: some View {
        NotchSegmentedPicker(
            options: ShortcutActionType.allCases,
            selection: $actionType,
            titleMapper: { $0.rawValue }
        )
    }

    @ViewBuilder
    private var actionInputField: some View {
        switch actionType {
        case .openURL:
            fieldRow(icon: "link", label: "URL") {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.88))
            }
        case .launchApp:
            fieldRow(icon: "app.badge", label: "Bundle ID") {
                TextField("com.apple.Safari", text: $bundleIDText)
                    .textFieldStyle(.plain)
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.88))
            }
        case .appleScript:
            VStack(alignment: .leading, spacing: 4) {
                Text("AppleScript Source")
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.38))
                TextEditor(text: $scriptText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 80)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                            .fill(NotchPanelFieldMetrics.fieldFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                            .stroke(NotchPanelFieldMetrics.fieldStroke, lineWidth: 1)
                    }
                    .scrollContentBackground(.hidden)
            }
        case .shellCommand:
            VStack(alignment: .leading, spacing: 4) {
                Text("Shell Command")
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.38))
                TextEditor(text: $shellText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 80)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                            .fill(NotchPanelFieldMetrics.fieldFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                            .stroke(NotchPanelFieldMetrics.fieldStroke, lineWidth: 1)
                    }
                    .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Validation & Save

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch actionType {
        case .openURL: return !urlText.trimmingCharacters(in: .whitespaces).isEmpty
        case .launchApp: return !bundleIDText.trimmingCharacters(in: .whitespaces).isEmpty
        case .appleScript: return !scriptText.trimmingCharacters(in: .whitespaces).isEmpty
        case .shellCommand: return !shellText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func saveItem() {
        let action: ShortcutAction
        switch actionType {
        case .openURL: action = .openURL(urlText.trimmingCharacters(in: .whitespaces))
        case .launchApp: action = .launchApp(bundleID: bundleIDText.trimmingCharacters(in: .whitespaces))
        case .appleScript: action = .appleScript(source: scriptText)
        case .shellCommand: action = .shellCommand(shellText.trimmingCharacters(in: .whitespaces))
        }

        if let existing = viewModel.editingItem {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.icon = icon
            updated.imagePath = imagePath
            updated.tintColor = tintColor
            updated.action = action
            viewModel.update(updated)
        } else {
            let item = ShortcutItem(
                name: name.trimmingCharacters(in: .whitespaces),
                icon: icon,
                imagePath: imagePath,
                tintColor: tintColor,
                action: action
            )
            viewModel.add(item)
        }
        viewModel.finishEditing()
    }

    // MARK: - Constants

    private let commonIcons = [
        "star", "globe", "app", "terminal",
        "link", "folder", "doc", "music.note",
        "message", "gearshape", "bolt", "book"
    ]

    private let colorOptions = [
        "blue", "purple", "orange", "green", "red",
        "yellow", "pink", "teal"
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
