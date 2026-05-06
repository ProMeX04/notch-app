import SwiftUI

struct ShortcutPanelView: View {
    @ObservedObject var viewModel: NotchShortcutViewModel
    @ObservedObject var presentationModel: NotchPresentationModel

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 72), spacing: 1)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasItems {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(viewModel.items) { item in
                            Button {
                                viewModel.execute(item)
                            } label: {
                                ShortcutTileView(item: item, accentColor: presentationModel.accentColor)
                            }
                            .buttonStyle(ShortcutTileButtonStyle())
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    viewModel.delete(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
                    .padding(.bottom, 46)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(10)
        }
        .alert(
            "Execution Error",
            isPresented: .init(
                get: { viewModel.executionError != nil },
                set: { if !$0 { viewModel.executionError = nil } }
            ),
            presenting: viewModel.executionError
        ) { errorInfo in
            Button("OK", role: .cancel) {}
        } message: { errorInfo in
            Text("\(errorInfo.itemName): \(errorInfo.message)")
        }
        .alert(
            "Confirm Execution",
            isPresented: .init(
                get: { viewModel.pendingApprovalItem != nil },
                set: { if !$0 { viewModel.resolveApproval(false) } }
            ),
            presenting: viewModel.pendingApprovalItem
        ) { item in
            Button("Cancel", role: .cancel) {
                viewModel.resolveApproval(false)
            }
            Button("Run") {
                viewModel.resolveApproval(true)
            }
        } message: { item in
            Text("\"\(item.name)\" wants to run a \(item.action.typeName). Allow?")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10])
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.72))

                    Text("Add shortcuts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116)
    }

    private var addButton: some View {
        Button {
            AppSettingsController.shared.open(tab: .shortcuts)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                .background(
                    Capsule()
                        .fill(presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78))
                )
        }
        .buttonStyle(.plain)
        .help("Add Shortcut")
    }
}

// MARK: - Tile

struct ShortcutTileView: View {
    let item: ShortcutItem
    let accentColor: Color

    @State private var isHovered = false

    private var tileColor: Color {
        ShortcutTintPalette.color(for: item.tintColor, fallback: accentColor)
    }

    private var brightTileColor: Color {
        tileColor.ensureMinimumBrightness(factor: 0.82)
    }

    var body: some View {
        VStack(spacing: 6) {
            ShortcutArtworkView(
                item: item,
                size: 42,
                cornerRadius: 12,
                tint: brightTileColor
            )
            .shadow(color: brightTileColor.opacity(isHovered ? 0.22 : 0.10), radius: isHovered ? 10 : 4, y: 3)

            Text(item.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 64, maxWidth: 72, minHeight: 82)
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct ShortcutTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
