import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class WindowShareSelectionController: NSObject, @unchecked Sendable, SCContentSharingPickerObserver {
    private let picker = SCContentSharingPicker.shared
    private var completion: ((SCContentFilter?) -> Void)?
    private var isObserving = false

    func beginSelection(completion: @escaping (SCContentFilter?) -> Void) {
        cancelSelection(notify: false)
        self.completion = completion

        if !isObserving {
            picker.add(self)
            isObserving = true
        }

        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleApplication]
        configuration.allowsChangingSelectedContent = false

        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }

        if let windowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber {
            configuration.excludedWindowIDs = [windowNumber]
        }

        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.isActive = true

        NSApp.activate(ignoringOtherApps: true)
        picker.present(using: .window)
    }

    func cancelSelection(notify: Bool = true) {
        let completion = notify ? self.completion : nil
        teardown()
        completion?(nil)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.finish(with: nil)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.finish(with: filter)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: nil)
        }
    }

    private func finish(with filter: SCContentFilter?) {
        let completion = self.completion
        teardown()
        completion?(filter)
    }

    private func teardown() {
        picker.isActive = false
        if isObserving {
            picker.remove(self)
            isObserving = false
        }
        completion = nil
    }
}
