import AppKit
import SwiftUI

enum ShortcutTintPalette {
    static func color(for name: String, fallback: Color = Color(nsColor: .systemBlue)) -> Color {
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
        case "cyan": return Color(nsColor: .systemCyan)
        default: return fallback
        }
    }
}

struct ShortcutArtworkView: View {
    let item: ShortcutItem
    let size: CGFloat
    var cornerRadius: CGFloat
    var tint: Color? = nil

    private var resolvedTint: Color {
        tint ?? ShortcutTintPalette.color(for: item.tintColor)
    }

    private var resolvedImage: NSImage? {
        if let imagePath = item.normalizedImagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            return image
        }

        if case .launchApp(let bundleID) = item.action,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(nsImage: resolvedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    resolvedTint.ensureMinimumBrightness(factor: 0.86).opacity(0.95),
                                    resolvedTint.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: item.icon)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
