import AppKit
import SwiftUI

struct GeminiFileTextEditor: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var isLightChrome: Bool { colorScheme == .light }
    private var fillColor: Color { isLightChrome ? .black.opacity(0.04) : .white.opacity(0.08) }
    private var strokeColor: Color { isLightChrome ? .black.opacity(0.1) : .white.opacity(0.12) }
    private var textColor: Color { isLightChrome ? .black.opacity(0.9) : .white.opacity(0.9) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)

            RoundedRectangle(cornerRadius: 10)
                .stroke(strokeColor, lineWidth: 1)

            TextEditor(text: $text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(textColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(minHeight: 180)
    }
}
struct GeminiToolsPicker: View {
    @Binding var selection: Set<GeminiTool>
    var lockedTools: Set<GeminiTool> = []
    var isDisabled = false
    @State private var showExecWarning = false
    @State private var showFDAWarning = false
    @State private var pendingFDATool: GeminiTool?
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSelectableTools: Set<GeminiTool> {
        Set(GeminiTool.coreCases).union(GeminiTool.restrictedTools).subtracting(lockedTools)
    }

    /// Bulk "Enable All" never turns on shell (`exec`) silently; user must confirm via the exec row.
    /// FDA-gated tools are skipped when access is missing (no Settings deep link spam).
    private var bulkEnableTools: Set<GeminiTool> {
        var base = allSelectableTools.subtracting([.exec])
        if !SystemPermissionsManager.shared.hasFullDiskAccess() {
            base.subtract([.appleMail, .localFileSearch])
        }
        return base
    }

    private var hasAllToolsSelected: Bool {
        !bulkEnableTools.isEmpty && selection.isSuperset(of: bulkEnableTools)
    }

    private var allToolsList: [GeminiTool] {
        GeminiTool.coreCases + GeminiTool.restrictedTools.subtracting(GeminiTool.coreToolSet).sorted { $0.rawValue < $1.rawValue }
    }

    private var summaryText: String {
        let effectiveCount = selection.union(lockedTools).count
        switch effectiveCount {
        case 0:
            return Localization.get("No tools", lang: appLanguage)
        case GeminiTool.coreCases.count:
            return Localization.get("All tools", lang: appLanguage)
        default:
            return "\(effectiveCount) \(Localization.get("tools", lang: appLanguage))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Localization.get("Core Tools", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                Button {
                    if hasAllToolsSelected {
                        selection = []
                    } else {
                        selection = bulkEnableTools
                    }
                } label: {
                    Text(Localization.get(hasAllToolsSelected ? "Disable All" : "Enable All", lang: appLanguage))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeAccent)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            .padding(.bottom, 2)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(allToolsList) { tool in
                    let isLocked = lockedTools.contains(tool)
                    let isSelected = selection.contains(tool) || isLocked
                    
                    HStack(spacing: 8) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 14)
                            .foregroundStyle(isSelected ? themeAccent : .white.opacity(0.4))
                        
                        Text(Localization.get(tool.displayName, lang: appLanguage))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                            .lineLimit(1)
                        
                        Spacer(minLength: 0)
                        
                        Toggle("", isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                guard !isLocked else { return }
                                if newValue {
                                    // Only exec uses the shell warning; skillWriter enables like other tools.
                                    if tool == .exec {
                                        showExecWarning = true
                                        return
                                    }
                                    if tool == .appleMail || tool == .localFileSearch {
                                        if !SystemPermissionsManager.shared.hasFullDiskAccess() {
                                            pendingFDATool = tool
                                            showFDAWarning = true
                                            return
                                        }
                                    }
                                    selection.insert(tool)
                                } else {
                                    selection.remove(tool)
                                }
                            }
                        ))
                        .toggleStyle(NotchSwitchStyle(tint: themeAccent))
                        .disabled(isLocked || isDisabled)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? themeAccent.opacity(0.18) : Color.clear, lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .alert("⚠️ Enable Shell Access?", isPresented: $showExecWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Enable", role: .destructive) {
                selection.insert(.exec)
            }
        } message: {
            Text("Exec allows the AI to run arbitrary shell commands on your Mac. This is risky in a voice conversation — the AI may execute commands you don't expect. Only enable this if you fully understand the risks.")
        }
        .alert("🔒 Full Disk Access Required", isPresented: $showFDAWarning) {
            Button("Cancel", role: .cancel) {
                pendingFDATool = nil
            }
            Button("Open System Settings") {
                SystemPermissionsManager.shared.openFullDiskAccessSettings()
                // We don't insert yet because they haven't granted it yet.
                // They'll need to toggle again after granting.
                pendingFDATool = nil
            }
        } message: {
            let toolName = pendingFDATool?.displayName ?? "This tool"
            Text("\(toolName) requires Full Disk Access to read local data. Please add Notch to the Full Disk Access list in System Settings > Privacy & Security.")
        }
    }
}
struct GeminiSkillsPicker: View {
    let installedSkills: [InstalledSkill]
    @Binding var selection: Set<String>
    var isDisabled = false
    var onCreateInEditor: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var onDuplicate: ((String) -> Void)? = nil
    var onDelete: ((String) -> Void)? = nil

    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSkillIDs: Set<String> {
        Set(installedSkills.map(\.id))
    }

    private var hasAllSkillsSelected: Bool {
        !installedSkills.isEmpty && selection.isSuperset(of: allSkillIDs)
    }

    private func isUserManaged(_ skill: InstalledSkill) -> Bool {
        skill.source != .builtin
    }

    private var sortedSkills: [InstalledSkill] {
        installedSkills.sorted { s1, s2 in
            let u1 = isUserManaged(s1)
            let u2 = isUserManaged(s2)
            if u1 != u2 {
                return u1
            }
            return s1.metadata.name < s2.metadata.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Localization.get("Skills", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                if let onCreateInEditor {
                    Button(action: onCreateInEditor) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(Localization.get("New Skill", lang: appLanguage))
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                }

                Button {
                    if hasAllSkillsSelected {
                        selection = []
                    } else {
                        selection = allSkillIDs
                    }
                } label: {
                    Text(Localization.get(hasAllSkillsSelected ? "Disable All" : "Enable All", lang: appLanguage))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            if installedSkills.isEmpty {
                Text(Localization.get("No skills installed", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ForEach(sortedSkills, id: \.id) { skill in
                    let isSelected = selection.contains(skill.id)

                    HStack(spacing: 8) {
                        Color.clear
                            .frame(width: 14, height: 12)

                        Text(skill.metadata.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))

                        if isUserManaged(skill) {
                            Text("User")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(themeAccent.opacity(0.2))
                                .cornerRadius(4)
                        } else if skill.source == .builtin {
                            Text("Built-in")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }

                        Spacer()

                        if onEdit != nil || onDuplicate != nil || onDelete != nil {
                            Menu {
                                if let onEdit {
                                    Button {
                                        onEdit(skill.id)
                                    } label: {
                                        Label(Localization.get("Edit", lang: appLanguage), systemImage: "pencil")
                                    }
                                }
                                if let onDuplicate {
                                    Button {
                                        onDuplicate(skill.id)
                                    } label: {
                                        Label(Localization.get("Duplicate", lang: appLanguage), systemImage: "doc.on.doc")
                                    }
                                }
                                if isUserManaged(skill), let onDelete {
                                    Button(role: .destructive) {
                                        onDelete(skill.id)
                                    } label: {
                                        Label(Localization.get("Delete", lang: appLanguage), systemImage: "trash")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(isDisabled)
                        }

                        Toggle("", isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                if newValue {
                                    selection.insert(skill.id)
                                } else {
                                    selection.remove(skill.id)
                                }
                            }
                        ))
                        .toggleStyle(NotchSwitchStyle(tint: themeAccent))
                        .disabled(isDisabled)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Avatar only (used as `Menu` label). Agent name is shown as a label below.
