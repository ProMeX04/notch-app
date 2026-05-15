import AppKit
import SwiftUI

struct GeminiDualPill: View {
    let leftIcon: String
    let leftTitle: String
    let leftSubtitle: String
    let rightIcon: String
    let rightTitle: String
    let rightSubtitle: String
    let tint: Color
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: leftIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(leftTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(leftSubtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            Spacer(minLength: 12)
            
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rightTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(rightSubtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Image(systemName: rightIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(isHovering ? tint.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
    }
}
struct GeminiAgentStatusDualPill: View {
    let voice: String
    let thinking: String
    let tint: Color
    let lang: String
    
    var body: some View {
        GeminiDualPill(
            leftIcon: "waveform",
            leftTitle: voice,
            leftSubtitle: Localization.get("Giọng nói", lang: lang),
            rightIcon: "sparkles",
            rightTitle: thinking,
            rightSubtitle: Localization.get("Suy nghĩ", lang: lang),
            tint: tint
        )
    }
}
struct GeminiAgentAvatarArtwork: View {
    let imageURL: URL?
    let symbolName: String
    let symbolFont: Font
    let size: CGFloat

    @State private var loadedImage: NSImage?

    private static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 20
        return cache
    }()

    private static func loadImageAsync(from url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        // Move file read off the main thread
        let image = await Task.detached {
            NSImage(contentsOf: url)
        }.value
        
        if let image {
            imageCache.setObject(image, forKey: key)
        }
        return image
    }

    var body: some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .clipped()
            } else {
                Image(systemName: symbolName)
                    .font(symbolFont)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size, height: size)
            }
        }
        .task(id: imageURL) {
            guard let imageURL else {
                loadedImage = nil
                return
            }
            if let cached = Self.imageCache.object(forKey: imageURL as NSURL) {
                loadedImage = cached
            } else {
                loadedImage = await Self.loadImageAsync(from: imageURL)
            }
        }
    }
}
struct GeminiAgentHomeAvatarFigure: View {
    let statusColor: Color
    var avatarSymbolName: String = GeminiSystemPromptPreset.defaultAvatarSymbolName
    var avatarImageURL: URL? = nil
    @State private var animPhase: Double = 0
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Modern Waveform Visualizer (Behind Avatar)
            HStack(spacing: 102) { // Tighter gap
                waveformGroup(isLeft: true)
                waveformGroup(isLeft: false)
            }
            .frame(width: 200)
            .opacity(isHovering ? 1.0 : 0.8)
            .blur(radius: 0.5)

            // Inner Shadow/Glow for the Avatar
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 100, height: 100)
                .shadow(color: statusColor.opacity(isHovering ? 0.7 : 0.4), radius: isHovering ? 25 : 15)

            // Avatar Container
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 94, height: 94)
                    .overlay {
                        Circle()
                            .stroke(statusColor.opacity(isHovering ? 0.5 : 0.3), lineWidth: isHovering ? 2 : 1.5)
                            .frame(width: 94, height: 94)
                    }

                GeminiAgentAvatarArtwork(
                    imageURL: avatarImageURL,
                    symbolName: avatarSymbolName,
                    symbolFont: .system(size: 36, weight: .medium),
                    size: 94
                )
                .clipShape(Circle())
            }
        }
        .scaleEffect(isHovering ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .frame(width: 108, height: 100, alignment: .top)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animPhase = 1.0
            }
        }
    }

    @ViewBuilder
    private func waveformGroup(isLeft: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(statusColor)
                    .frame(width: 2, height: heightForBar(i, isLeft: isLeft))
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
            }
        }
    }

    private func heightForBar(_ index: Int, isLeft: Bool) -> CGFloat {
        // Tapering off from avatar: [24, 16, 10, 6, 3]
        let heights: [CGFloat] = [24, 16, 10, 6, 3]
        
        let baseH: CGFloat
        if isLeft {
            // Left group: index 4 is closest to the avatar (right-most in group)
            baseH = heights[4 - index]
        } else {
            // Right group: index 0 is closest to the avatar (left-most in group)
            baseH = heights[index]
        }
        return baseH + (animPhase * 3)
    }
}
struct GeminiAgentSelectionView: View {
    let prompts: [GeminiSystemPromptPreset]
    let selectedID: String
    let statusColor: Color
    let onSelect: (String) -> Void
    let onCreate: () -> Void
    let onDone: () -> Void

    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var currentPage: Int = 0

    private let pageSize = 5

    private var totalItems: Int {
        prompts.count + 1 // +1 for the "New Agent" button
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(totalItems) / Double(pageSize))))
    }

    private var currentIndices: Range<Int> {
        let start = currentPage * pageSize
        let end = min(start + pageSize, totalItems)
        return start..<end
    }

    private var isLastPage: Bool { currentPage == totalPages - 1 }

    private let columns = [
        GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Agent grid — fixed size so it naturally expands parent
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(currentIndices, id: \.self) { index in
                    if index < prompts.count {
                        let prompt = prompts[index]
                        AgentSelectionCard(
                            prompt: prompt,
                            isSelected: prompt.id == selectedID,
                            statusColor: statusColor,
                            action: { onSelect(prompt.id) }
                        )
                    } else {
                        // "New Agent" button is always the very last item overall
                        Button(action: onCreate) {
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                        .frame(width: 58, height: 58)

                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                                .frame(width: 74, height: 74)

                                Text(Localization.get("New Agent", lang: appLanguage))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.42))
                                    .lineLimit(1)
                                    .tracking(0.2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)

            Spacer(minLength: 0)

            // Pagination controls — only shown when needed
            if totalPages > 1 {
                HStack(spacing: 12) {
                    // Prev button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            currentPage = max(0, currentPage - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(currentPage == 0 ? .white.opacity(0.2) : .white.opacity(0.75))
                            .frame(width: 24, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(currentPage == 0 ? 0.04 : 0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0)

                    // Page dots
                    HStack(spacing: 5) {
                        ForEach(0..<totalPages, id: \.self) { idx in
                            Circle()
                                .fill(idx == currentPage ? statusColor : Color.white.opacity(0.22))
                                .frame(width: idx == currentPage ? 6 : 4, height: idx == currentPage ? 6 : 4)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Next button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            currentPage = min(totalPages - 1, currentPage + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isLastPage ? .white.opacity(0.2) : .white.opacity(0.75))
                            .frame(width: 24, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(isLastPage ? 0.04 : 0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLastPage)
                }
                .padding(.top, 0)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .onChange(of: prompts.count) { _, _ in
            // Clamp page if agents were deleted
            currentPage = min(currentPage, max(0, totalPages - 1))
        }
    }
}
struct AgentSelectionCard: View {
    let prompt: GeminiSystemPromptPreset
    let isSelected: Bool
    let statusColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 74, height: 74)
                            .blur(radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [statusColor.opacity(0.9), statusColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .stroke(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                        }
                        .shadow(color: isSelected ? statusColor.opacity(0.3) : .clear, radius: 8, y: 4)

                    GeminiAgentAvatarArtwork(
                        imageURL: prompt.resolvedAvatarImageURL,
                        symbolName: prompt.resolvedAvatarSymbolName,
                        symbolFont: .system(size: 22, weight: .medium),
                        size: 58
                    )
                    
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(statusColor).padding(1))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .frame(width: 58, height: 58)
                    }
                }
                .frame(width: 74, height: 74)
                
                Text(formattedAgentDisplayName(prompt.title))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.82))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
                    .frame(height: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}
