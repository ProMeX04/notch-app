import Foundation

enum NotchPanel: String {
    case music
    case focus
    case talk
    case shelf
}

enum FocusTool: String {
    case pomodoro
    case countdown
    case counter
}

@MainActor
final class NotchPresentationModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var isPinnedOpen = false
    @Published var closedNotchSize: CGSize = CGSize(width: 184, height: 32)
    @Published var selectedPanel: NotchPanel = .music
    @Published var selectedFocusTool: FocusTool = .pomodoro

    private var collapseTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?

    func setHovering(_ hovering: Bool) {
        if hovering {
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                self.reveal()
            }
            return
        }

        hoverOpenTask?.cancel()
        scheduleCollapse()
    }

    func reveal() {
        hoverOpenTask?.cancel()
        collapseTask?.cancel()
        isExpanded = true
    }

    func selectPanel(_ panel: NotchPanel, reveal: Bool = false) {
        selectedPanel = panel
        if reveal {
            self.reveal()
        }
    }

    func scheduleCollapse(after duration: Duration = .milliseconds(900)) {
        collapseTask?.cancel()

        guard !isPinnedOpen else { return }

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isExpanded = false
        }
    }

    func togglePinned() {
        isPinnedOpen.toggle()
        if isPinnedOpen {
            reveal()
        } else {
            scheduleCollapse(after: .milliseconds(100))
        }
    }

    func toggleExpanded() {
        if isExpanded && !isPinnedOpen {
            scheduleCollapse(after: .zero)
        } else {
            reveal()
        }
    }
}
