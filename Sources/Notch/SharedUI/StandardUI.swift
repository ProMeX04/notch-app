import SwiftUI

// MARK: - Shared metrics (Notch chrome)

enum StandardButtonMetrics {
    /// Capsule row height (was 32pt; −20%).
    static let height: CGFloat = 25.6
    static let font: Font = .system(size: 11, weight: .bold)
    static let horizontalPadding: CGFloat = 12
}

/// Universal action button style for the entire project.
/// ~25.6pt height, Bold 11 font, Capsule shape (`StandardButtonMetrics`).
struct StandardActionButton: View {
    let title: String
    var icon: String? = nil
    let tint: Color
    var variant: Variant = .secondary
    var isDisabled: Bool = false
    /// When true, the button expands to fill the parent `HStack` / `VStack` width (e.g. toolbars).
    var fillsAvailableWidth: Bool = false
    let action: () -> Void
    
    enum Variant {
        case primary
        case secondary
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(StandardButtonMetrics.font)
                }
                
                Text(title)
                    .font(StandardButtonMetrics.font)
            }
            .foregroundStyle(variant == .primary ? .black : tint)
            .padding(.horizontal, StandardButtonMetrics.horizontalPadding)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .center)
            .frame(height: StandardButtonMetrics.height)
            .background(
                Capsule()
                    .fill(variant == .primary ? tint : tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

// MARK: - Menu / custom control chrome matching primary pill buttons

/// Primary pill chrome (filled accent capsule, dark label) — use inside `Menu` labels or custom layouts to match `StandardActionButton` primary.
struct StandardPrimaryPillChrome: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint)
    }
}

extension View {
    /// Primary pill label styling aligned with `StandardActionButton` (`.primary`).
    func standardPrimaryPillLabelStyle(
        tint: Color,
        fillsWidth: Bool = true
    ) -> some View {
        self
            .font(StandardButtonMetrics.font)
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, StandardButtonMetrics.horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: StandardButtonMetrics.height)
            .background(StandardPrimaryPillChrome(tint: tint))
            .contentShape(Rectangle())
    }
}

// MARK: - Menu field rows (Gemini Talk, Focus quick settings)

/// Shared metrics for dropdown/menu fields — matches pre-connect Talk chrome.
enum NotchPanelFieldMetrics {
    static let corner: CGFloat = 9
    static let hPad: CGFloat = 10
    static let vPad: CGFloat = 6
    static var minHeight: CGFloat { StandardButtonMetrics.height }
    static let iconColWidth: CGFloat = 14
    static let labelFont = Font.system(size: 10, weight: .semibold)
    static let chevronFont = Font.system(size: 9, weight: .bold)
    static let fieldFill = Color.white.opacity(0.06)
    static let fieldStroke = Color.white.opacity(0.08)
}

/// Leading icon + title + trailing chevron/ellipsis; rounded rect fill matching Talk tools.
struct NotchMenuFieldRow: View {
    enum TrailingGlyph {
        case chevron
        case ellipsis
        case none
    }

    let leadingIcon: String
    let title: String
    var trailing: TrailingGlyph = .chevron
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingIcon)
                .font(NotchPanelFieldMetrics.labelFont)
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)
            Text(title)
                .font(NotchPanelFieldMetrics.labelFont)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Group {
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.up.chevron.down")
                        .font(NotchPanelFieldMetrics.chevronFont)
                case .ellipsis:
                    Image(systemName: "ellipsis")
                        .font(NotchPanelFieldMetrics.labelFont)
                case .none:
                    EmptyView()
                }
            }
            .foregroundStyle(isDestructive ? Color.red.opacity(0.45) : .white.opacity(0.38))
        }
        .foregroundStyle(isDestructive ? Color.red.opacity(0.88) : .white.opacity(0.78))
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
}

// MARK: - Interactive Button Styles

struct GrowingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Custom Segmented Picker

struct NotchSegmentedPicker<T: Identifiable & Equatable>: View where T.ID == String {
    let options: [T]
    @Binding var selection: T
    let titleMapper: (T) -> String
    var tint: Color = .blue
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection == option
                
                Button {
                    selection = option
                } label: {
                    Text(titleMapper(option))
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .black.opacity(0.85) : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(tint)
                                    .matchedGeometryEffect(id: "segment", in: animationNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.06).cornerRadius(9))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    }
    
    @Namespace private var animationNamespace
}


