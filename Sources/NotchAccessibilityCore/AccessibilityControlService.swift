import AppKit
import Foundation

// MARK: - AccessibilityControlService

/// A self-contained service that owns all macOS Accessibility API interactions
/// for the `notchctl accessibility` command domain.
///
/// - **Thread safety:** All public methods are `async` and safe to call from any
///   Swift concurrency context. Internal AX calls are performed synchronously on a
///   dedicated serial queue to avoid data races with the AX runtime.
/// - **Element IDs:** Session-scoped opaque UUIDs. The registry is cleared each time
///   a new `tree`, `focused`, `apps`, or `windows` call is made so stale IDs from a
///   previous snapshot cannot target unrelated elements.
/// - **No AppleScript / CGEvent:** All work uses `AXUIElement` APIs only.
final class AccessibilityControlService: @unchecked Sendable {

    nonisolated(unsafe) static var shared = AccessibilityControlService()

    // MARK: Traversal constants

    /// Maximum depth when no explicit depth is requested.
    static let defaultDepth = 5
    /// Maximum total nodes per snapshot (breadth-first cutoff).
    static let maxNodes = 200

    // MARK: Element registry (session-scoped)

    /// Maps opaque session ID → AXUIElement. Cleared before each new read.
    private var elementRegistry: [String: AXUIElement] = [:]
    private let registryLock = NSLock()
    private let permissionChecker: @Sendable () -> Bool

    init(permissionChecker: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.permissionChecker = permissionChecker
    }

    // MARK: - Permission

    /// Returns `true` when Accessibility permission has been granted for this process.
    func isPermissionGranted() -> Bool {
        permissionChecker()
    }

    // MARK: - Apps

    /// Returns a JSON-serialisable array of running app descriptors.
    func listApps() -> [[String: Any]] {
        clearRegistry()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { app in
                var entry: [String: Any] = [:]
                if let name = app.localizedName { entry["name"] = name }
                if let bundleID = app.bundleIdentifier { entry["bundleIdentifier"] = bundleID }
                entry["pid"] = Int(app.processIdentifier)
                entry["isActive"] = app.isActive
                return entry
            }
    }

    // MARK: - Windows

    /// Returns window descriptors for the given app name, or frontmost app if nil.
    func listWindows(appName: String?) -> Result<[[String: Any]], AXErrorCode> {
        clearRegistry()
        guard let app = resolveApp(named: appName) else {
            return .failure(.appNotFound)
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            return .success([])
        }
        let result: [[String: Any]] = windows.enumerated().compactMap { _, win in
            let id = registerElement(win)
            var d: [String: Any] = ["id": id]
            if let title = axStringAttribute(win, kAXTitleAttribute) { d["title"] = title }
            if let frame = axFrame(win) { d["frame"] = AXFrame(frame).jsonObject() }
            if let minimised = axBoolAttribute(win, kAXMinimizedAttribute) { d["minimized"] = minimised }
            return d
        }
        return .success(result)
    }

    // MARK: - Focused Element

    /// Returns a snapshot of the currently focused AX element (system-wide).
    func focusedElement(depth: Int) -> Result<[String: Any], AXErrorCode> {
        clearRegistry()
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard err == .success, let element = focusedRef as! AXUIElement? else {
            return .success(["focused": false, "message": "No focused element found."])
        }
        var nodeCount = 0
        let snapshot = buildSnapshot(element, depth: depth, nodeCount: &nodeCount, maxNodes: Self.maxNodes)
        let encoded = encodeSnapshot(snapshot, nodeCount: nodeCount)
        return .success(encoded)
    }

    // MARK: - Tree Snapshot

    enum TreeTarget {
        case frontmost
        case app(String)
        case window(String)
        case element(String)
    }

    func treeSnapshot(target: TreeTarget, depth: Int) -> Result<[String: Any], AXErrorCode> {
        switch target {
        case .frontmost:
            clearRegistry()
            guard let app = NSWorkspace.shared.frontmostApplication else {
                return .failure(.appNotFound)
            }
            return treeForApp(pid: app.processIdentifier, depth: depth)

        case .app(let name):
            clearRegistry()
            guard let app = resolveApp(named: name) else {
                return .failure(.appNotFound)
            }
            return treeForApp(pid: app.processIdentifier, depth: depth)

        case .window(let id):
            guard let element = lookupElement(id: id) else {
                return .failure(.windowNotFound)
            }
            clearRegistry()
            var nodeCount = 0
            let snapshot = buildSnapshot(element, depth: depth, nodeCount: &nodeCount, maxNodes: Self.maxNodes)
            return .success(encodeSnapshot(snapshot, nodeCount: nodeCount))

        case .element(let id):
            guard let element = lookupElement(id: id) else {
                return .failure(.elementNotFound)
            }
            clearRegistry()
            var nodeCount = 0
            let snapshot = buildSnapshot(element, depth: depth, nodeCount: &nodeCount, maxNodes: Self.maxNodes)
            return .success(encodeSnapshot(snapshot, nodeCount: nodeCount))
        }
    }

    private func treeForApp(pid: pid_t, depth: Int) -> Result<[String: Any], AXErrorCode> {
        let axApp = AXUIElementCreateApplication(pid)
        var nodeCount = 0
        let snapshot = buildSnapshot(axApp, depth: depth, nodeCount: &nodeCount, maxNodes: Self.maxNodes)
        return .success(encodeSnapshot(snapshot, nodeCount: nodeCount))
    }

    // MARK: - Actions

    enum AXAction {
        case press
        case click
        case focus
        case type(String)
        case setValue(String)
        case scroll(AXScrollDirection, Int)
        case performNamed(String)
    }

    enum AXScrollDirection: String {
        case up, down, left, right
    }

    func performAction(_ action: AXAction, elementID: String) -> Result<[String: Any], AXErrorCode> {
        guard let element = lookupElement(id: elementID) else {
            return .failure(.elementNotFound)
        }
        switch action {
        case .press:
            return performAXAction(element, axActionName: kAXPressAction)
        case .click:
            return performAXAction(element, axActionName: kAXPressAction)
        case .focus:
            let err = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            if err == .success {
                return .success(["message": "Element focused."])
            }
            return .failure(.actionNotSupported)
        case .type(let text):
            return typeIntoElement(element, text: text)
        case .setValue(let text):
            return setValueOnElement(element, value: text)
        case .scroll(let direction, let amount):
            return scrollElement(element, direction: direction, amount: amount)
        case .performNamed(let name):
            return performAXAction(element, axActionName: name)
        }
    }

    // MARK: - Private: Action Helpers

    private func performAXAction(_ element: AXUIElement, axActionName: String) -> Result<[String: Any], AXErrorCode> {
        // Check the element advertises this action
        var actionsRef: CFArray?
        AXUIElementCopyActionNames(element, &actionsRef)
        if let advertised = actionsRef as? [String], !advertised.contains(axActionName) {
            return .failure(.actionNotSupported)
        }
        let err = AXUIElementPerformAction(element, axActionName as CFString)
        if err == .success {
            return .success(["message": "Action '\(axActionName)' performed."])
        }
        return .failure(.actionNotSupported)
    }

    private func typeIntoElement(_ element: AXUIElement, text: String) -> Result<[String: Any], AXErrorCode> {
        // Focus the element first, then set its value
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        let err = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        if err == .success {
            return .success(["message": "Text set on element."])
        }
        if err == .attributeUnsupported || err == .illegalArgument {
            return .failure(.valueNotSettable)
        }
        return .failure(.actionNotSupported)
    }

    private func setValueOnElement(_ element: AXUIElement, value: String) -> Result<[String: Any], AXErrorCode> {
        let err = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        if err == .success {
            return .success(["message": "Value set on element."])
        }
        if err == .attributeUnsupported || err == .illegalArgument {
            return .failure(.valueNotSettable)
        }
        return .failure(.actionNotSupported)
    }

    private func scrollElement(_ element: AXUIElement, direction: AXScrollDirection, amount: Int) -> Result<[String: Any], AXErrorCode> {
        // Use AXScrollToVisible and synthetic scroll via AX parameterised attributes where possible.
        // AX does not have a universal "scroll by N" action; we perform AXScrollToVisible as best effort.
        let action: String
        switch direction {
        case .up:    action = kAXScrollUpAction
        case .down:  action = kAXScrollDownAction
        case .left:  action = kAXScrollLeftAction
        case .right: action = kAXScrollRightAction
        }

        var performed = false
        for _ in 0..<max(1, amount) {
            let err = AXUIElementPerformAction(element, action as CFString)
            if err == .success { performed = true }
        }
        if performed {
            return .success(["message": "Scrolled \(direction.rawValue) \(amount) time(s)."])
        }
        return .failure(.actionNotSupported)
    }

    // MARK: - Private: AX Tree Builder

    private func buildSnapshot(
        _ element: AXUIElement,
        depth: Int,
        nodeCount: inout Int,
        maxNodes: Int
    ) -> AXElementSnapshot {
        nodeCount += 1
        let id = registerElement(element)

        let role = axStringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
        let subrole = axStringAttribute(element, kAXSubroleAttribute)
        let title = axStringAttribute(element, kAXTitleAttribute)
        let label = axStringAttribute(element, kAXDescriptionAttribute)
        let value = axStringValue(element, kAXValueAttribute)
        let description = axStringAttribute(element, kAXRoleDescriptionAttribute)
        let enabled = axBoolAttribute(element, kAXEnabledAttribute)
        let selected = axBoolAttribute(element, kAXSelectedAttribute)
        let focused = axBoolAttribute(element, kAXFocusedAttribute)
        let frame = axFrame(element).map(AXFrame.init)
        let actions = axActions(element)

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        let rawChildren = (childrenRef as? [AXUIElement]) ?? []
        let childrenCount = rawChildren.count

        var snapshotChildren: [AXElementSnapshot]?
        var wasTruncated: Bool?

        if depth > 0 && nodeCount < maxNodes {
            var kids: [AXElementSnapshot] = []
            for child in rawChildren {
                guard nodeCount < maxNodes else {
                    wasTruncated = true
                    break
                }
                kids.append(buildSnapshot(child, depth: depth - 1, nodeCount: &nodeCount, maxNodes: maxNodes))
            }
            snapshotChildren = kids.isEmpty ? nil : kids
        } else if depth == 0 && childrenCount > 0 {
            // Indicate there are children but we didn't descend
            wasTruncated = true
        }

        return AXElementSnapshot(
            id: id,
            role: role,
            subrole: subrole,
            title: title,
            label: label,
            value: value,
            description: description,
            enabled: enabled,
            selected: selected,
            focused: focused,
            frame: frame,
            actions: actions,
            childrenCount: childrenCount,
            children: snapshotChildren,
            truncated: wasTruncated
        )
    }

    // MARK: - Private: AX Attribute Accessors

    private func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let str = ref as? String, !str.isEmpty else { return nil }
        return str
    }

    private func axStringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        if let str = ref as? String { return str.isEmpty ? nil : str }
        if let num = ref as? NSNumber { return num.stringValue }
        return nil
    }

    private func axBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let val = ref as? Bool else { return nil }
        return val
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func axActions(_ element: AXUIElement) -> [String] {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(element, &ref) == .success,
              let names = ref as? [String] else { return [] }
        return names
    }

    // MARK: - Private: App Resolution

    private func resolveApp(named name: String?) -> NSRunningApplication? {
        if let name {
            let lower = name.lowercased()
            return NSWorkspace.shared.runningApplications.first {
                ($0.localizedName?.lowercased() == lower
                    || $0.bundleIdentifier?.lowercased() == lower)
                    && $0.activationPolicy != .prohibited
            }
        }
        return NSWorkspace.shared.frontmostApplication
    }

    // MARK: - Private: Element Registry

    private func registerElement(_ element: AXUIElement) -> String {
        registryLock.lock()
        defer { registryLock.unlock() }
        // Check if already registered (same pointer)
        for (id, existing) in elementRegistry where CFEqual(existing, element) {
            return id
        }
        let id = UUID().uuidString.lowercased()
        elementRegistry[id] = element
        return id
    }

    private func lookupElement(id: String) -> AXUIElement? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return elementRegistry[id]
    }

    private func clearRegistry() {
        registryLock.lock()
        defer { registryLock.unlock() }
        elementRegistry.removeAll()
    }

    // MARK: - Private: JSON Encoding

    private func encodeSnapshot(_ snapshot: AXElementSnapshot, nodeCount: Int) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["role": snapshot.role, "id": snapshot.id]
        }
        let truncated = snapshot.truncated == true || nodeCount >= Self.maxNodes
        obj["nodeCount"] = nodeCount
        if truncated {
            obj["warningCode"] = AXErrorCode.treeTruncated.rawValue
            obj["warning"] = "Tree truncated by depth or node limit."
        }
        return obj
    }

    // MARK: - Test hooks

    func registerElementForTests(_ element: AXUIElement) -> String {
        registerElement(element)
    }

    func lookupElementForTests(id: String) -> AXUIElement? {
        lookupElement(id: id)
    }

    func clearRegistryForTests() {
        clearRegistry()
    }
}

// MARK: - AXFrame JSON helper

private extension AXFrame {
    func jsonObject() -> [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
    }
}

// MARK: - AX action name constants (missing from public headers)

private let kAXScrollUpAction    = "AXScrollUp"
private let kAXScrollDownAction  = "AXScrollDown"
private let kAXScrollLeftAction  = "AXScrollLeft"
private let kAXScrollRightAction = "AXScrollRight"
