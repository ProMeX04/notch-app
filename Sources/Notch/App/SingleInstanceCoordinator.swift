import AppKit
import Foundation

final class SingleInstanceCoordinator {
    private let notificationCenter: DistributedNotificationCenter
    private let runningApplications: (String) -> [NSRunningApplication]
    private let bundleIdentifier: () -> String?
    private let currentProcessIdentifier: () -> pid_t
    private var activationObserver: NSObjectProtocol?

    init(
        notificationCenter: DistributedNotificationCenter = .default(),
        runningApplications: @escaping (String) -> [NSRunningApplication] = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        },
        bundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier },
        currentProcessIdentifier: @escaping () -> pid_t = { ProcessInfo.processInfo.processIdentifier }
    ) {
        self.notificationCenter = notificationCenter
        self.runningApplications = runningApplications
        self.bundleIdentifier = bundleIdentifier
        self.currentProcessIdentifier = currentProcessIdentifier
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func registerActivationHandler(_ handler: @escaping @Sendable () -> Void) {
        unregisterActivationHandler()

        guard let notificationName = activationNotificationName else { return }

        activationObserver = notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { _ in
            DispatchQueue.main.async(execute: handler)
        }
    }

    func unregisterActivationHandler() {
        guard let activationObserver else { return }
        notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    func shouldTerminateForExistingInstance() -> Bool {
        guard let bundleIdentifier = bundleIdentifier() else { return false }

        let currentProcessIdentifier = currentProcessIdentifier()
        let existingApplication = runningApplications(bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }
            .sorted(by: Self.isOlderApplication)
            .first

        guard let existingApplication else { return false }

        if let notificationName = activationNotificationName {
            notificationCenter.postNotificationName(
                notificationName,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }

        existingApplication.activate(options: [.activateAllWindows])
        return true
    }

    private var activationNotificationName: Notification.Name? {
        guard let bundleIdentifier = bundleIdentifier() else { return nil }
        return Notification.Name("\(bundleIdentifier).activate-existing-instance")
    }

    private static func isOlderApplication(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        let lhsLaunchDate = lhs.launchDate ?? .distantPast
        let rhsLaunchDate = rhs.launchDate ?? .distantPast

        if lhsLaunchDate != rhsLaunchDate {
            return lhsLaunchDate < rhsLaunchDate
        }

        return lhs.processIdentifier < rhs.processIdentifier
    }
}
