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
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSelectableTools: Set<GeminiTool> {
        Set(GeminiTool.coreCases).union(GeminiTool.restrictedTools).subtracting(lockedTools)
    }

    private var hasAllToolsSelected: Bool {
        !allSelectableTools.isEmpty && selection.isSuperset(of: allSelectableTools)
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
                        selection = allSelectableTools
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
    }
}
