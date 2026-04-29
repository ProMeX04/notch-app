import Foundation

struct AccessibilityEntitlementStatus: Sendable {
    let isAllowed: Bool
    let statusLabel: String
    let message: String
}

enum AccessibilityCommandHandler {
    static func handle(
        tokens: [String],
        service: AccessibilityControlService,
        entitlementStatus: AccessibilityEntitlementStatus?
    ) -> [String: Any] {
        let cmdLabel = "notchctl accessibility \(tokens.joined(separator: " "))"
        let subcommand = tokens.first?.lowercased()
        let args = Array(tokens.dropFirst())

        if subcommand == "status" {
            let permissionGranted = service.isPermissionGranted()
            let entitlementLabel = entitlementStatus?.statusLabel ?? "unknown"
            let entitlementMessage = entitlementStatus?.message.isEmpty == false
                ? entitlementStatus!.message
                : (entitlementStatus?.isAllowed == false
                    ? "Accessibility Control requires Notch Pro."
                    : "Accessibility Control available.")
            return axSuccess([
                "permissionGranted": permissionGranted,
                "proEntitlement": entitlementLabel,
                "message": permissionGranted
                    ? entitlementMessage
                    : "Accessibility permission not granted."
            ], command: cmdLabel)
        }

        if let entitlementStatus, !entitlementStatus.isAllowed {
            return AXErrorCode.requiresPro.result(
                message: entitlementStatus.message.isEmpty
                    ? "Accessibility Control requires Notch Pro."
                    : entitlementStatus.message,
                command: cmdLabel
            )
        }

        if !service.isPermissionGranted() {
            var result = AXErrorCode.permissionDenied.result(
                message: "Notch does not have Accessibility permission. "
                    + "Open System Settings -> Privacy & Security -> Accessibility and enable Notch, "
                    + "then try again.",
                command: cmdLabel
            )
            result["recoveryAction"] = "openAccessibilitySettings"
            return result
        }

        guard let subcommand else {
            return AXErrorCode.unsupportedTarget.result(
                message: "Missing subcommand. Usage: notchctl accessibility <status|apps|windows|focused|tree|click|press|focus|type|set-value|scroll|action>",
                command: cmdLabel
            )
        }

        switch subcommand {
        case "apps":
            let apps = service.listApps()
            return axSuccess(["apps": apps, "count": apps.count], command: cmdLabel)

        case "windows":
            let appName = flagValue("--app", in: args) ?? flagValue("-app", in: args)
            switch service.listWindows(appName: appName) {
            case .success(let windows):
                return axSuccess(["windows": windows, "count": windows.count], command: cmdLabel)
            case .failure(let code):
                return code.result(
                    message: appName.map { "App '\($0)' not found." } ?? "No frontmost app.",
                    command: cmdLabel
                )
            }

        case "focused":
            let depth = intArg(at: 0, in: args) ?? AccessibilityControlService.defaultDepth
            switch service.focusedElement(depth: depth) {
            case .success(let data):
                return axSuccess(data, command: cmdLabel)
            case .failure(let code):
                return code.result(message: "Could not resolve focused element.", command: cmdLabel)
            }

        case "tree":
            let (treeTarget, depth) = parseTreeArgs(args)
            switch treeTarget {
            case .failure(let code):
                return code.result(message: "Invalid tree target.", command: cmdLabel)
            case .success(let target):
                switch service.treeSnapshot(target: target, depth: depth) {
                case .success(let data):
                    return axSuccess(data, command: cmdLabel)
                case .failure(let code):
                    return code.result(message: axTreeErrorMessage(code, args: args), command: cmdLabel)
                }
            }

        case "click", "press":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            let action: AccessibilityControlService.AXAction = subcommand == "click" ? .click : .press
            return axActionResult(service.performAction(action, elementID: elementID), command: cmdLabel)

        case "focus":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            return axActionResult(service.performAction(.focus, elementID: elementID), command: cmdLabel)

        case "type":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            let text = Array(args.dropFirst()).joined(separator: " ")
            return axActionResult(service.performAction(.type(text), elementID: elementID), command: cmdLabel)

        case "set-value", "setvalue":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            let value = Array(args.dropFirst()).joined(separator: " ")
            return axActionResult(service.performAction(.setValue(value), elementID: elementID), command: cmdLabel)

        case "scroll":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            let dirStr = args.dropFirst().first?.lowercased() ?? "down"
            guard let direction = AccessibilityControlService.AXScrollDirection(rawValue: dirStr) else {
                return AXErrorCode.unsupportedTarget.result(
                    message: "Invalid scroll direction '\(dirStr)'. Use: up, down, left, right.",
                    command: cmdLabel
                )
            }
            let amount = args.count >= 3 ? (Int(args[2]) ?? 1) : 1
            return axActionResult(service.performAction(.scroll(direction, amount), elementID: elementID), command: cmdLabel)

        case "action":
            guard let elementID = args.first else {
                return AXErrorCode.elementNotFound.result(message: "Missing element ID.", command: cmdLabel)
            }
            guard let actionName = args.dropFirst().first else {
                return AXErrorCode.actionNotSupported.result(message: "Missing action name.", command: cmdLabel)
            }
            return axActionResult(service.performAction(.performNamed(actionName), elementID: elementID), command: cmdLabel)

        default:
            return AXErrorCode.unsupportedTarget.result(
                message: "Unknown accessibility subcommand '\(subcommand)'. "
                    + "Supported: status, apps, windows, focused, tree, click, press, focus, type, set-value, scroll, action.",
                command: cmdLabel
            )
        }
    }

    private static func parseTreeArgs(_ args: [String]) -> (Result<AccessibilityControlService.TreeTarget, AXErrorCode>, Int) {
        var remaining = args
        var depth = AccessibilityControlService.defaultDepth

        if remaining.count >= 2, remaining[remaining.count - 2].lowercased() == "depth",
           let n = Int(remaining[remaining.count - 1]) {
            depth = max(1, min(n, 10))
            remaining = Array(remaining.dropLast(2))
        }

        let first = remaining.first?.lowercased()
        switch first {
        case nil, "frontmost":
            return (.success(.frontmost), depth)
        case "app":
            let name = Array(remaining.dropFirst()).joined(separator: " ")
            guard !name.isEmpty else { return (.failure(.appNotFound), depth) }
            return (.success(.app(name)), depth)
        case "window":
            guard let id = remaining.dropFirst().first else { return (.failure(.windowNotFound), depth) }
            return (.success(.window(id)), depth)
        case "element":
            guard let id = remaining.dropFirst().first else { return (.failure(.elementNotFound), depth) }
            return (.success(.element(id)), depth)
        default:
            return (.failure(.unsupportedTarget), depth)
        }
    }

    private static func axActionResult(_ result: Result<[String: Any], AXErrorCode>, command: String) -> [String: Any] {
        switch result {
        case .success(let data):
            return axSuccess(data, command: command)
        case .failure(let code):
            let msg: String
            switch code {
            case .elementNotFound: msg = "Element not found in current session. Call tree or focused first."
            case .actionNotSupported: msg = "This element does not support the requested action."
            case .valueNotSettable: msg = "This element's value cannot be set."
            default: msg = "Action failed."
            }
            return code.result(message: msg, command: command)
        }
    }

    private static func axTreeErrorMessage(_ code: AXErrorCode, args: [String]) -> String {
        switch code {
        case .appNotFound: return "App '\(args.dropFirst().joined(separator: " "))' is not running."
        case .elementNotFound: return "Element ID not found in current session."
        case .windowNotFound: return "Window ID not found in current session."
        default: return "Could not build AX tree."
        }
    }

    private static func flagValue(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func intArg(at index: Int, in args: [String]) -> Int? {
        guard index < args.count else { return nil }
        return Int(args[index])
    }
}
