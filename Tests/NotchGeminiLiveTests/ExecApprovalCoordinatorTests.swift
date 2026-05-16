import Foundation
import NotchGeminiLiveCore

final class ApprovalCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(command: String, workingDirectory: String?)] = []

    func append(command: String, workingDirectory: String?) {
        lock.lock()
        calls.append((command, workingDirectory))
        lock.unlock()
    }

    var snapshot: [(command: String, workingDirectory: String?)] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

@MainActor
enum ExecApprovalCoordinatorTests {
    static let allTests: [TestCase] = [
        TestCase(name: "exec-approval/enqueue appends first request", run: enqueueAppendsFirstRequest),
        TestCase(name: "exec-approval/enqueue ignores duplicate tool call ID", run: enqueueIgnoresDuplicateToolCallID),
        TestCase(name: "exec-approval/approve once removes current", run: approveOnceRemovesCurrent),
        TestCase(name: "exec-approval/deny removes current", run: denyRemovesCurrent),
        TestCase(name: "exec-approval/clear all empties queue", run: clearAllEmptiesQueue),
        TestCase(name: "exec-approval/approve always exact records approval", run: approveAlwaysExactRecordsApproval),
        TestCase(name: "exec-approval/approve always family records approval", run: approveAlwaysFamilyRecordsApproval),
        TestCase(name: "exec-approval/auto approve delegates to actions", run: autoApproveDelegatesToActions),
        TestCase(name: "exec-approval/command family handles env and basename", run: commandFamilyHandlesEnvAndBasename),
    ]

    static func enqueueAppendsFirstRequest() throws {
        let state = makeState()
        let request = makeRequest(id: "call-1", command: "ls -la")

        state.enqueue(request)

        try expectEqual(state.pending.count, 1, "pending count")
        try expectEqual(state.pending.first, request, "pending first request")
    }

    static func enqueueIgnoresDuplicateToolCallID() throws {
        let state = makeState()
        let first = makeRequest(id: "call-1", command: "ls -la")
        let duplicate = makeRequest(id: "call-1", command: "pwd")

        state.enqueue(first)
        state.enqueue(duplicate)

        try expectEqual(state.pending.count, 1, "pending count")
        try expectEqual(state.pending.first, first, "duplicate should not replace first request")
    }

    static func approveOnceRemovesCurrent() throws {
        let state = makeState()
        state.enqueue(makeRequest(id: "call-1", command: "ls"))
        state.enqueue(makeRequest(id: "call-2", command: "pwd"))

        let approvedID = state.approveCurrentOnce()

        try expectEqual(approvedID, "call-1", "approved ID")
        try expectEqual(state.pending.map(\.toolCallID), ["call-2"], "remaining pending IDs")
    }

    static func denyRemovesCurrent() throws {
        let state = makeState()
        state.enqueue(makeRequest(id: "call-1", command: "ls"))
        state.enqueue(makeRequest(id: "call-2", command: "pwd"))

        let deniedID = state.denyCurrent()

        try expectEqual(deniedID, "call-1", "denied ID")
        try expectEqual(state.pending.map(\.toolCallID), ["call-2"], "remaining pending IDs")
    }

    static func clearAllEmptiesQueue() throws {
        let state = makeState()
        state.enqueue(makeRequest(id: "call-1"))
        state.enqueue(makeRequest(id: "call-2"))

        state.clearAll()

        try expect(state.pending.isEmpty, "pending should be empty")
    }

    static func approveAlwaysExactRecordsApproval() throws {
        let exactApprovals = ApprovalCallRecorder()
        let state = makeState(
            approveExact: { command, workingDirectory in
                exactApprovals.append(command: command, workingDirectory: workingDirectory)
            }
        )
        state.enqueue(makeRequest(id: "call-1", command: "swift build", workingDirectory: "/tmp/project"))
        state.enqueue(makeRequest(id: "call-2", command: "pwd"))

        let approvedID = state.approveCurrentAlwaysExact()

        let exactApprovalSnapshot = exactApprovals.snapshot
        try expectEqual(exactApprovalSnapshot.count, 1, "exact approval count")
        try expectEqual(exactApprovalSnapshot.first?.command, "swift build", "exact command")
        try expectEqual(exactApprovalSnapshot.first?.workingDirectory, "/tmp/project", "exact working directory")
        try expectEqual(approvedID, "call-1", "approved ID")
        try expectEqual(state.pending.map(\.toolCallID), ["call-2"], "remaining pending IDs")
    }

    static func approveAlwaysFamilyRecordsApproval() throws {
        let familyApprovals = ApprovalCallRecorder()
        let state = makeState(
            approveFamily: { command, workingDirectory in
                familyApprovals.append(command: command, workingDirectory: workingDirectory)
            }
        )
        state.enqueue(makeRequest(id: "call-1", command: "swift build", workingDirectory: "/tmp/project"))
        state.enqueue(makeRequest(id: "call-2", command: "pwd"))

        let approvedID = state.approveCurrentAlwaysFamily()

        let familyApprovalSnapshot = familyApprovals.snapshot
        try expectEqual(familyApprovalSnapshot.count, 1, "family approval count")
        try expectEqual(familyApprovalSnapshot.first?.command, "swift build", "family command")
        try expectEqual(familyApprovalSnapshot.first?.workingDirectory, "/tmp/project", "family working directory")
        try expectEqual(approvedID, "call-1", "approved ID")
        try expectEqual(state.pending.map(\.toolCallID), ["call-2"], "remaining pending IDs")
    }

    static func autoApproveDelegatesToActions() throws {
        let checked = ApprovalCallRecorder()
        let state = makeState(
            isApproved: { command, workingDirectory in
                checked.append(command: command, workingDirectory: workingDirectory)
                return command == "swift build"
            }
        )

        let approved = state.shouldAutoApprove(command: "swift build", workingDirectory: "/tmp/project")
        let denied = state.shouldAutoApprove(command: "rm -rf build", workingDirectory: nil)

        try expect(approved, "swift build should be approved by seam")
        try expect(!denied, "rm command should not be approved by seam")
        let checkedSnapshot = checked.snapshot
        try expectEqual(checkedSnapshot.count, 2, "checked count")
        try expectEqual(checkedSnapshot.first?.command, "swift build", "first checked command")
        try expectEqual(checkedSnapshot.first?.workingDirectory, "/tmp/project", "first checked working directory")
        try expectEqual(checkedSnapshot.last?.command, "rm -rf build", "last checked command")
        try expectEqual(checkedSnapshot.last?.workingDirectory, nil, "last checked working directory")
    }

    static func commandFamilyHandlesEnvAndBasename() throws {
        try expectEqual(execCommandFamily(for: "env FOO=bar /usr/bin/swift build"), "swift", "env basename family")
        try expectEqual(execCommandFamily(for: "  npm test"), "npm", "simple family")
        try expectEqual(execCommandFamily(for: "FOO=bar make test"), "make", "assignment family")
        try expectEqual(execCommandFamily(for: "   "), nil, "blank family")
    }

    private static func makeState(
        isApproved: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Bool = { _, _ in false },
        approveExact: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Void = { _, _ in },
        approveFamily: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Void = { _, _ in }
    ) -> ExecApprovalState {
        ExecApprovalState(
            actions: ExecApprovalActions(
                isApproved: isApproved,
                approveExact: approveExact,
                approveFamily: approveFamily
            )
        )
    }

    private static func makeRequest(
        id: String,
        command: String = "ls",
        workingDirectory: String? = nil,
        timeoutSeconds: Double = 30
    ) -> ExecApprovalRequest {
        ExecApprovalRequest(
            toolCallID: id,
            command: command,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        )
    }
}
