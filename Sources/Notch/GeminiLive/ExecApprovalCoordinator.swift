import Combine
import Foundation

@MainActor
final class ExecApprovalCoordinator: ObservableObject {
    @Published private(set) var pending: [ExecApprovalRequest] = []

    nonisolated private let store: GeminiLiveExecApprovalStore

    var onApprove: (@MainActor (_ toolCallID: String) -> Void)?
    var onDeny: (@MainActor (_ toolCallID: String) -> Void)?

    init(store: GeminiLiveExecApprovalStore) {
        self.store = store
    }

    func enqueue(_ request: ExecApprovalRequest) {
        guard !pending.contains(where: { $0.toolCallID == request.toolCallID }) else { return }
        pending.append(request)
    }

    func clearAll() {
        pending.removeAll()
    }

    func approveCurrentOnce() {
        guard let request = pending.first else { return }
        pending.removeAll { $0.toolCallID == request.toolCallID }
        onApprove?(request.toolCallID)
    }

    func approveCurrentAlwaysExact() {
        guard let request = pending.first else { return }
        store.approveExact(command: request.command, workingDirectory: request.workingDirectory)
        pending.removeAll { $0.toolCallID == request.toolCallID }
        onApprove?(request.toolCallID)
    }

    func approveCurrentAlwaysFamily() {
        guard let request = pending.first else { return }
        store.approveFamily(command: request.command, workingDirectory: request.workingDirectory)
        pending.removeAll { $0.toolCallID == request.toolCallID }
        onApprove?(request.toolCallID)
    }

    func denyCurrent() {
        guard let request = pending.first else { return }
        pending.removeAll { $0.toolCallID == request.toolCallID }
        onDeny?(request.toolCallID)
    }

    nonisolated func shouldAutoApprove(command: String, workingDirectory: String?) -> Bool {
        store.isApproved(command: command, workingDirectory: workingDirectory)
    }
}

@MainActor
extension GeminiLiveViewModel {
    var currentPendingExecApproval: ExecApprovalRequest? {
        pendingExecApprovals.first
    }

    func configureExecApprovalCallbacks() {
        let approvals = execApprovals
        session.onShouldAutoApproveExec = { command, workingDirectory in
            approvals.shouldAutoApprove(command: command, workingDirectory: workingDirectory)
        }

        session.onExecApprovalRequested = { [weak self] request in
            DispatchQueue.main.async {
                self?.handleExecApprovalRequest(request)
            }
        }
    }

    func handleExecApprovalRequest(_ request: ExecApprovalRequest) {
        execApprovals.enqueue(request)
        postToolAction(
            label: "Command approval needed",
            icon: "terminal",
            showsInOverlay: false,
            autoClearAfter: nil
        )
        onExecApprovalAttentionRequested?()
    }

    func approveCurrentExecApprovalOnce() {
        execApprovals.approveCurrentOnce()
    }

    func approveCurrentExecApprovalExact() {
        execApprovals.approveCurrentAlwaysExact()
    }

    func approveCurrentExecApprovalFamily() {
        execApprovals.approveCurrentAlwaysFamily()
    }

    func denyCurrentExecApproval() {
        execApprovals.denyCurrent()
    }
}
