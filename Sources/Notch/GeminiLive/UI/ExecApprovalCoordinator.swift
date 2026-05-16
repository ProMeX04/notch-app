import Combine
import Foundation
import NotchGeminiLiveCore

@MainActor
final class ExecApprovalCoordinator: ObservableObject {
    @Published private(set) var pending: [ExecApprovalRequest] = []

    private let state: ExecApprovalState

    var onApprove: (@MainActor (_ toolCallID: String) -> Void)?
    var onDeny: (@MainActor (_ toolCallID: String) -> Void)?

    init(store: GeminiLiveExecApprovalStore) {
        self.state = ExecApprovalState(
            actions: ExecApprovalActions(
                isApproved: { command, workingDirectory in
                    store.isApproved(command: command, workingDirectory: workingDirectory)
                },
                approveExact: { command, workingDirectory in
                    store.approveExact(command: command, workingDirectory: workingDirectory)
                },
                approveFamily: { command, workingDirectory in
                    store.approveFamily(command: command, workingDirectory: workingDirectory)
                }
            )
        )
    }

    init(state: ExecApprovalState) {
        self.state = state
    }

    func enqueue(_ request: ExecApprovalRequest) {
        state.enqueue(request)
        pending = state.pending
    }

    func clearAll() {
        state.clearAll()
        pending = state.pending
    }

    func approveCurrentOnce() {
        guard let toolCallID = state.approveCurrentOnce() else { return }
        pending = state.pending
        onApprove?(toolCallID)
    }

    func approveCurrentAlwaysExact() {
        guard let toolCallID = state.approveCurrentAlwaysExact() else { return }
        pending = state.pending
        onApprove?(toolCallID)
    }

    func approveCurrentAlwaysFamily() {
        guard let toolCallID = state.approveCurrentAlwaysFamily() else { return }
        pending = state.pending
        onApprove?(toolCallID)
    }

    func denyCurrent() {
        guard let toolCallID = state.denyCurrent() else { return }
        pending = state.pending
        onDeny?(toolCallID)
    }

    nonisolated func shouldAutoApprove(command: String, workingDirectory: String?) -> Bool {
        state.shouldAutoApprove(command: command, workingDirectory: workingDirectory)
    }
}

extension ExecApprovalCoordinator {
    func allApprovedEntries() -> [GeminiLiveExecApprovalStore.ApprovedEntry] {
        let store = GeminiLiveExecApprovalStore()
        return store.allApprovedEntries()
    }

    func removeApprovedEntry(key: String) {
        let store = GeminiLiveExecApprovalStore()
        store.removeApproval(key: key)
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
