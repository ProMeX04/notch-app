import AppKit
import Carbon.HIToolbox

/// Lightweight CGEvent remapper used by Notch Settings → Shortcuts.
final class QuickKeyEngine: @unchecked Sendable {
    static let shared = QuickKeyEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?

    private let lock = NSLock()
    private var isSynthesizing = false
    private var isPaused = false
    private var engineEnabled = true
    private var byKeyCode: [Int: [QuickKeyMapping]] = [:]
    private var watchesModifiers = false
    private var frontmostBundleID: String?

    private init() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            self?.lock.lock()
            self?.frontmostBundleID = bid
            self?.lock.unlock()
        }

        NotificationCenter.default.addObserver(
            forName: .quickKeyMappingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadMappings()
            }
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    /// Call once from app bootstrap.
    @MainActor
    func bootstrap() {
        QuickKeyAccessibility.shared.refresh()
        if QuickKeyStore.shared.isEngineEnabled, QuickKeyAccessibility.shared.isTrusted {
            start()
        }
    }

    @MainActor
    func reloadMappings() {
        let store = QuickKeyStore.shared
        let enabled = store.isEngineEnabled
        var index: [Int: [QuickKeyMapping]] = [:]
        var needsModifiers = false
        if enabled {
            for mapping in store.mappings where mapping.isEnabled {
                index[mapping.triggerKeyCode, default: []].append(mapping)
                if QuickKeyModifier.isModifierKeyCode(mapping.triggerKeyCode) {
                    needsModifiers = true
                }
            }
        }
        lock.lock()
        engineEnabled = enabled
        byKeyCode = index
        watchesModifiers = needsModifiers
        lock.unlock()
    }

    @MainActor
    func start() {
        stopTapOnly()
        reloadMappings()
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<QuickKeyEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    @MainActor
    func stop() {
        stopTapOnly()
        lock.lock()
        byKeyCode = [:]
        engineEnabled = false
        watchesModifiers = false
        lock.unlock()
    }

    @MainActor
    private func stopTapOnly() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    @MainActor
    func restartIfNeeded() {
        guard QuickKeyStore.shared.isEngineEnabled, QuickKeyAccessibility.shared.isTrusted else {
            stop()
            return
        }
        if eventTap == nil {
            start()
        } else if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            reloadMappings()
        }
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        lock.unlock()
    }

    // MARK: - Hot path

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let enabled = engineEnabled
        let paused = isPaused
        let synthesizing = isSynthesizing
        let watchMods = watchesModifiers
        guard enabled, !paused, !synthesizing else {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged, !watchMods {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }

        guard let candidates = byKeyCode[keyCode], !candidates.isEmpty else {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }

        let maps = candidates
        let front = frontmostBundleID
        lock.unlock()

        if type == .flagsChanged {
            return handleFlagsChanged(event: event, keyCode: keyCode, maps: maps, front: front)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = event.flags.rawValue & QuickKeyChord.relevantModifierMask
        guard let mapping = match(maps: maps, modifiers: modifiers, frontBundle: front) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            synthesize(mapping)
        }
        return nil
    }

    private func handleFlagsChanged(
        event: CGEvent,
        keyCode: Int,
        maps: [QuickKeyMapping],
        front: String?
    ) -> Unmanaged<CGEvent>? {
        guard QuickKeyModifier.isDown(keyCode: keyCode, cgFlags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }
        guard let mapping = match(maps: maps, modifiers: 0, frontBundle: front) else {
            return Unmanaged.passUnretained(event)
        }
        synthesize(mapping)
        return nil
    }

    private func match(maps: [QuickKeyMapping], modifiers: UInt64, frontBundle: String?) -> QuickKeyMapping? {
        var globalHit: QuickKeyMapping?
        for mapping in maps {
            guard mapping.triggerModifiers == modifiers else { continue }
            if let bid = mapping.appBundleID, !bid.isEmpty {
                if bid == frontBundle { return mapping }
            } else if globalHit == nil {
                globalHit = mapping
            }
        }
        return globalHit
    }

    private func synthesize(_ mapping: QuickKeyMapping) {
        lock.lock()
        isSynthesizing = true
        lock.unlock()
        defer {
            lock.lock()
            isSynthesizing = false
            lock.unlock()
        }

        let targetCode = CGKeyCode(mapping.targetKeyCode)
        let flags = CGEventFlags(rawValue: mapping.targetModifiers)
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        if QuickKeyModifier.isModifierKeyCode(Int(targetCode)) {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: targetCode, keyDown: true) {
                down.flags = flags.union(QuickKeyModifier.flag(for: Int(targetCode)))
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: targetCode, keyDown: false) {
                up.flags = flags
                up.post(tap: .cgSessionEventTap)
            }
            return
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: targetCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: targetCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cgSessionEventTap)
        }
    }
}
