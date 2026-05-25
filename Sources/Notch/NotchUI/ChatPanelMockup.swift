import SwiftUI


struct ChatPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Chat Scroll Area
            ScrollView {
                VStack(spacing: 24) {
                    UserMessageBubble(text: "hello")
                    ModelMessageBubble(
                        text: "Hello there! How can I help you today?",
                        duration: "0:02"
                    )
                }
                .padding(20)
            }

            // Bottom Status Bar
            BottomStatusBar()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Message Bubbles

struct UserMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("User")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)

                Text(text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

struct ModelMessageBubble: View {
    let text: String
    let duration: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 12) {
                    // Audio Player Mockup
                    AudioPlayerMockup(duration: duration)

                    // Caption Text
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)

                    // Disclaimer
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Google AI models may make mistakes, so double-check outputs.")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // subtle border
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            Spacer()
        }
    }
}

// MARK: - Components

struct AudioPlayerMockup: View {
    let duration: String

    var body: some View {
        HStack(spacing: 12) {
            Button { } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Text("0:00 / \(duration)")
                .font(.system(size: 12, design: .monospaced))

            // Progress Bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: proxy.size.width * 0.1, height: 4) // 10% progress
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 80)

            Button { } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}

struct BottomStatusBar: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                }

                HStack(spacing: 8) {
                    Text("Stream is live")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Button { } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
    }
}

struct ChatPanelView_Previews: PreviewProvider {
    static var previews: some View {
        ChatPanelView()
            .preferredColorScheme(.dark)
            .frame(width: 450, height: 600)
    }
}
