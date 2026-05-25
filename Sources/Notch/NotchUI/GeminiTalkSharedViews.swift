import AppKit
import SwiftUI

func themedNotchAccentColor(from accentColorID: String) -> Color {
    NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
}
func formattedAgentDisplayName(_ raw: String) -> String {
    let collapsed = raw
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return collapsed.isEmpty ? "Untitled Agent" : collapsed
}
struct GeminiTalkPanelCard<Content: View>: View {
    let tint: Color?
    let content: Content

    init(
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.085),
                                Color.white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint?.opacity(0.28) ?? Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}
struct GeminiTalkStateBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.16))
        )
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
}
struct GeminiActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        StandardActionButton(
            title: title,
            icon: icon,
            tint: tint,
            variant: .primary,
            action: action
        )
    }
}

/// Shared pill chrome for live controls (`GeminiControlToggle`, screen share picker).
struct GeminiSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        StandardActionButton(
            title: title,
            icon: nil,
            tint: .white,
            variant: .primary,
            action: action
        )
    }
}
struct GeminiTranscriptCard: View {
    let title: String
    let text: String
    let placeholder: String
    var revealsProgressively = false
    var showsFullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(showsFullText ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Group {
                        if revealsProgressively {
                            ProgressiveRevealText(text: text, animateOnAppear: false)
                        } else {
                            Text(text)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(showsFullText ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}
struct GeminiDropdownPicker<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let label: String
    /// Leading SF Symbol; matches other Gemini menus (prompt, tools).
    var leadingIcon: String = "slider.horizontal.3"
    @Binding var selection: T
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var buttonTitle: String {
        "\(label): \(Localization.get(selection.rawValue, lang: appLanguage))"
    }

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(Localization.get(item.rawValue, lang: appLanguage), systemImage: "checkmark")
                    } else {
                        Text(Localization.get(item.rawValue, lang: appLanguage))
                    }
                }
            }
        } label: {
            NotchMenuFieldRow(leadingIcon: leadingIcon, title: buttonTitle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct GeminiPillPicker<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let title: String
    let icon: String // e.g. "speaker.fill"
    let tint: Color // e.g. Color.yellow
    @Binding var selection: T
    let displayText: (T) -> String
    @AppStorage("app_language") private var appLanguage: String = "English"

    init(
        title: String,
        icon: String,
        tint: Color,
        selection: Binding<T>,
        displayText: @escaping (T) -> String = { $0.rawValue }
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        _selection = selection
        self.displayText = displayText
    }

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(Localization.get(displayText(item), lang: appLanguage), systemImage: "checkmark")
                    } else {
                        Text(Localization.get(displayText(item), lang: appLanguage))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localization.get(displayText(selection), lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    if !title.isEmpty {
                        Text(Localization.get(title, lang: appLanguage))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
struct GeminiPillButton: View {
    let title: String
    var icon: String? = nil
    let tint: Color
    var isDisabled: Bool = false
    /// Expands each pill to equal width inside a shared `HStack` row (e.g. 2×2 grid).
    var fillsAvailableWidth: Bool = false
    let action: () -> Void

    var body: some View {
        StandardActionButton(
            title: title,
            icon: icon,
            tint: tint,
            variant: .primary,
            isDisabled: isDisabled,
            fillsAvailableWidth: fillsAvailableWidth,
            action: action
        )
    }
}
struct NotchSwitchStyle: ToggleStyle {
    var tint: Color = Color.blue

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Rectangle()
                .fill(configuration.isOn ? tint : Color.white.opacity(0.1))
                .frame(width: 24, height: 14)
                .overlay(
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 5 : -5)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
                .cornerRadius(7)
        }
    }
}
