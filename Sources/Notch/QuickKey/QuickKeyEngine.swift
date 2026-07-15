import AppKit
import Carbon.HIToolbox

/// Lightweight CGEvent remapper: one trigger shortcut → one send shortcut.
/// Trigger supports keys, chords, multi-press, and extra mouse buttons (Middle / Mouse 4–5).
final class QuickKeyEngine: @unchecked Sendable {
    static let shared = QuickKeyEngine()

    /// Gap between multi-taps (double / triple).
    private static let multiPressInterval: CFTimeInterval = 0.38

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?

    private let lock = NSLock()
    private var isSynthesizing = false
    private var isPaused = false
    private var engineEnabled = true
    private var byKeyCode: [Int: [QuickKeyMapping]] = [:]
    private var watchesModifiers = false
    private var watchesMouse = false
    private var frontmostBundleID: String?

    /// Multi-tap in progress for a trigger shortcut.
    private var pendingMulti: PendingMultiPress?
    private var multiTimeoutWorkItem: DispatchWorkItem?

    private struct PendingMultiPress {
        let keyCode: Int
        let modifiers: UInt64
        let isModifier: Bool
        let isMouse: Bool
        /// Mappings that share this key/mods (app-scoped preferred set).
        let candidates: [QuickKeyMapping]
        var pressCount: Int
        var lastPressAt: CFAbsoluteTime
    }

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
        var needsMouse = false
        if enabled {
            for mapping in store.mappings where mapping.isEnabled {
                index[mapping.triggerKeyCode, default: []].append(mapping)
                if QuickKeyModifier.isModifierKeyCode(mapping.triggerKeyCode) {
                    needsModifiers = true
                }
                if QuickKeyMouse.isMouseKeyCode(mapping.triggerKeyCode) {
                    needsMouse = true
                }
            }
        }
        lock.lock()
        let mouseChanged = watchesMouse != needsMouse
        engineEnabled = enabled
        byKeyCode = index
        watchesModifiers = needsModifiers
        watchesMouse = needsMouse
        lock.unlock()
        // Mouse watch set changed → rebuild the event tap mask.
        if mouseChanged, eventTap != nil {
            start()
        }
    }

    @MainActor
    func start() {
        cancelPendingMulti(reinject: false)
        stopTapOnly()
        // Load index without re-entering start via mouseChanged.
        let store = QuickKeyStore.shared
        let enabled = store.isEngineEnabled
        var index: [Int: [QuickKeyMapping]] = [:]
        var needsModifiers = false
        var needsMouse = false
        if enabled {
            for mapping in store.mappings where mapping.isEnabled {
                index[mapping.triggerKeyCode, default: []].append(mapping)
                if QuickKeyModifier.isModifierKeyCode(mapping.triggerKeyCode) {
                    needsModifiers = true
                }
                if QuickKeyMouse.isMouseKeyCode(mapping.triggerKeyCode) {
                    needsMouse = true
                }
            }
        }
        lock.lock()
        engineEnabled = enabled
        byKeyCode = index
        watchesModifiers = needsModifiers
        watchesMouse = needsMouse
        lock.unlock()
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        var mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        if needsMouse {
            // Middle + side buttons arrive as otherMouse* with buttonNumber 2+.
            mask |=
                (1 << CGEventType.otherMouseDown.rawValue)
                | (1 << CGEventType.otherMouseUp.rawValue)
        }

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
        cancelPendingMulti(reinject: false)
        stopTapOnly()
        lock.lock()
        byKeyCode = [:]
        engineEnabled = false
        watchesModifiers = false
        watchesMouse = false
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
        if paused {
            cancelPendingMulti(reinject: false)
        }
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
        let watchMouse = watchesMouse
        let pending = pendingMulti
        let candidatesSnapshot = byKeyCode
        let front = frontmostBundleID
        lock.unlock()

        guard enabled, !paused, !synthesizing else {
            return Unmanaged.passUnretained(event)
        }

        if isMouseEventType(type) {
            guard watchMouse else {
                return Unmanaged.passUnretained(event)
            }
            return handleMouse(type: type, event: event, pending: pending, candidatesSnapshot: candidatesSnapshot, front: front)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // Companion events while multi-tapping.
        if let pending {
            if pending.isMouse {
                // Keyboard press interrupts a mouse multi-tap sequence.
                if type == .keyDown
                    || (type == .flagsChanged && QuickKeyModifier.isDown(keyCode: keyCode, cgFlags: event.flags)) {
                    cancelPendingMulti(reinject: true)
                    return handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyUp, keyCode == pending.keyCode, !pending.isModifier {
                return nil
            }
            if type == .flagsChanged, keyCode == pending.keyCode, pending.isModifier {
                let isDown = QuickKeyModifier.isDown(keyCode: keyCode, cgFlags: event.flags)
                if !isDown { return nil }
                // Second/third press of same modifier — fall through.
            }
            let isNewPress =
                type == .keyDown
                || (type == .flagsChanged && QuickKeyModifier.isDown(keyCode: keyCode, cgFlags: event.flags))
            if isNewPress, keyCode != pending.keyCode {
                cancelPendingMulti(reinject: true)
                return handle(type: type, event: event)
            }
        }

        if type == .flagsChanged, !watchMods {
            return Unmanaged.passUnretained(event)
        }

        guard let maps = candidatesSnapshot[keyCode], !maps.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            return handleFlagsChanged(event: event, keyCode: keyCode, maps: maps, front: front)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = event.flags.rawValue & QuickKeyChord.relevantModifierMask
        let matched = matchAll(maps: maps, modifiers: modifiers, frontBundle: front)
        guard !matched.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            return nil
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        return resolvePress(
            candidates: matched,
            keyCode: keyCode,
            modifiers: modifiers,
            isModifier: false,
            isMouse: false
        )
    }

    private func isMouseEventType(_ type: CGEventType) -> Bool {
        type == .otherMouseDown || type == .otherMouseUp
    }

    private func isMouseDownType(_ type: CGEventType) -> Bool {
        type == .otherMouseDown
    }

    private func isMouseUpType(_ type: CGEventType) -> Bool {
        type == .otherMouseUp
    }

    private func handleMouse(
        type: CGEventType,
        event: CGEvent,
        pending: PendingMultiPress?,
        candidatesSnapshot: [Int: [QuickKeyMapping]],
        front: String?
    ) -> Unmanaged<CGEvent>? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard QuickKeyMouse.isRemappableButton(button) else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = QuickKeyMouse.keyCode(forButton: button)

        if let pending {
            if pending.isMouse {
                if isMouseUpType(type), keyCode == pending.keyCode {
                    return nil
                }
                if isMouseDownType(type), keyCode != pending.keyCode {
                    cancelPendingMulti(reinject: true)
                    return handle(type: type, event: event)
                }
                // Same mouse button down again → multi-tap fallthrough below.
            } else if isMouseDownType(type) {
                cancelPendingMulti(reinject: true)
                return handle(type: type, event: event)
            } else {
                return Unmanaged.passUnretained(event)
            }
        }

        guard let maps = candidatesSnapshot[keyCode], !maps.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let matched = matchAll(maps: maps, modifiers: 0, frontBundle: front)
        guard !matched.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        if isMouseUpType(type) {
            // Swallow ups for active remaps (down already matched or multi pending).
            return nil
        }

        guard isMouseDownType(type) else {
            return Unmanaged.passUnretained(event)
        }

        return resolvePress(
            candidates: matched,
            keyCode: keyCode,
            modifiers: 0,
            isModifier: false,
            isMouse: true
        )
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
        let matched = matchAll(maps: maps, modifiers: 0, frontBundle: front)
        guard !matched.isEmpty else {
            return Unmanaged.passUnretained(event)
        }
        return resolvePress(
            candidates: matched,
            keyCode: keyCode,
            modifiers: 0,
            isModifier: true,
            isMouse: false
        )
    }

    private func resolvePress(
        candidates: [QuickKeyMapping],
        keyCode: Int,
        modifiers: UInt64,
        isModifier: Bool,
        isMouse: Bool
    ) -> Unmanaged<CGEvent>? {
        let maxRequired = candidates.map(\.triggerMode.pressCount).max() ?? 1

        // Fast path: only single-press mappings.
        if maxRequired == 1, let mapping = preferred(candidates, pressCount: 1) {
            cancelPendingMulti(reinject: true)
            synthesize(mapping)
            return nil
        }

        lock.lock()
        let existing = pendingMulti
        lock.unlock()

        if let pending = existing,
           pending.keyCode == keyCode,
           pending.modifiers == modifiers,
           pending.isMouse == isMouse {
            var next = pending
            next.pressCount += 1
            next.lastPressAt = CFAbsoluteTimeGetCurrent()

            if next.pressCount >= maxRequired {
                cancelPendingMulti(reinject: false)
                if let mapping = preferred(next.candidates, pressCount: next.pressCount)
                    ?? preferred(next.candidates, pressCount: maxRequired) {
                    synthesize(mapping)
                }
                return nil
            }

            lock.lock()
            pendingMulti = next
            lock.unlock()
            scheduleMultiTimeout()
            return nil
        }

        // First press of a multi-tap sequence (or restart).
        cancelPendingMulti(reinject: true)

        if maxRequired == 1, let mapping = preferred(candidates, pressCount: 1) {
            synthesize(mapping)
            return nil
        }

        lock.lock()
        pendingMulti = PendingMultiPress(
            keyCode: keyCode,
            modifiers: modifiers,
            isModifier: isModifier,
            isMouse: isMouse,
            candidates: candidates,
            pressCount: 1,
            lastPressAt: CFAbsoluteTimeGetCurrent()
        )
        lock.unlock()
        scheduleMultiTimeout()
        return nil
    }

    private func scheduleMultiTimeout() {
        multiTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onMultiPressTimeout()
        }
        multiTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.multiPressInterval, execute: work)
    }

    private func onMultiPressTimeout() {
        lock.lock()
        let pending = pendingMulti
        pendingMulti = nil
        multiTimeoutWorkItem = nil
        lock.unlock()

        guard let pending else { return }

        if let mapping = preferred(pending.candidates, pressCount: pending.pressCount) {
            synthesize(mapping)
            return
        }

        // No mapping for this press count — reinject original key(s) once.
        reinjectOriginal(
            keyCode: pending.keyCode,
            modifiers: pending.modifiers,
            isModifier: pending.isModifier
        )
    }

    private func cancelPendingMulti(reinject: Bool) {
        multiTimeoutWorkItem?.cancel()
        multiTimeoutWorkItem = nil

        lock.lock()
        let pending = pendingMulti
        pendingMulti = nil
        lock.unlock()

        guard reinject, let pending else { return }
        reinjectOriginal(
            keyCode: pending.keyCode,
            modifiers: pending.modifiers,
            isModifier: pending.isModifier
        )
    }

    private func reinjectOriginal(keyCode: Int, modifiers: UInt64, isModifier: Bool) {
        lock.lock()
        isSynthesizing = true
        lock.unlock()
        defer {
            lock.lock()
            isSynthesizing = false
            lock.unlock()
        }

        if QuickKeyMouse.isMouseKeyCode(keyCode),
           let button = QuickKeyMouse.buttonNumber(fromKeyCode: keyCode) {
            reinjectMouse(button: button)
            return
        }

        let code = CGKeyCode(keyCode)
        let flags = CGEventFlags(rawValue: modifiers)
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        if isModifier {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
                down.flags = flags.union(QuickKeyModifier.flag(for: keyCode))
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                up.flags = flags
                up.post(tap: .cgSessionEventTap)
            }
            return
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func reinjectMouse(button: Int) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let types = QuickKeyMouse.eventTypes(forButton: button)
        // Post at the current cursor location (quartz global coords).
        let nsPoint = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(nsPoint, $0.frame, false) })
            ?? NSScreen.main else { return }
        let height = screen.frame.maxY
        let location = CGPoint(x: nsPoint.x, y: height - nsPoint.y)
        let cgButton: CGMouseButton = {
            switch button {
            case 0: return .left
            case 1: return .right
            default: return .center
            }
        }()

        if let down = CGEvent(
            mouseEventSource: source,
            mouseType: types.down,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ) {
            down.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(
            mouseEventSource: source,
            mouseType: types.up,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ) {
            up.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            up.post(tap: .cgSessionEventTap)
        }
    }

    /// All mappings for this key+mods, app-specific preferred over global when both exist for same mode.
    private func matchAll(maps: [QuickKeyMapping], modifiers: UInt64, frontBundle: String?) -> [QuickKeyMapping] {
        var appHits: [QuickKeyMapping] = []
        var globalHits: [QuickKeyMapping] = []
        for mapping in maps {
            guard mapping.triggerModifiers == modifiers else { continue }
            if let bid = mapping.appBundleID, !bid.isEmpty {
                if bid == frontBundle { appHits.append(mapping) }
            } else {
                globalHits.append(mapping)
            }
        }
        // Prefer app-scoped when present for a press count; otherwise global.
        var byCount: [Int: QuickKeyMapping] = [:]
        for m in globalHits { byCount[m.triggerMode.pressCount] = m }
        for m in appHits { byCount[m.triggerMode.pressCount] = m }
        return byCount.values.sorted { $0.triggerMode.pressCount < $1.triggerMode.pressCount }
    }

    private func preferred(_ candidates: [QuickKeyMapping], pressCount: Int) -> QuickKeyMapping? {
        candidates.first { $0.triggerMode.pressCount == pressCount }
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
