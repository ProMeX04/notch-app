import Foundation
import AppKit

// MARK: - AXElementSnapshot

/// A compact, JSON-serialisable snapshot of a single AXUIElement.
///
/// `id` is an opaque, session-scoped string created by `AccessibilityControlService`
/// at the time the snapshot is generated. It is stable within one snapshot/action
/// flow and can be passed back to action commands (click, press, type, etc.).
/// It must not be assumed to be valid across sessions or after the service is reset.
struct AXElementSnapshot: Encodable {
    /// Opaque session-scoped element identifier.
    let id: String
    /// AX role string, e.g. "AXButton".
    let role: String
    /// AX subrole string, e.g. "AXCloseButton". Omitted when absent.
    let subrole: String?
    /// AX title attribute.
    let title: String?
    /// AX label / description attribute used as accessible label.
    let label: String?
    /// AX value attribute (text fields, sliders, checkboxes, etc.).
    let value: String?
    /// AX roleDescription, a localised human-readable role.
    let description: String?
    /// Whether the element is enabled (`AXEnabled`).
    let enabled: Bool?
    /// Whether the element is selected (`AXSelected`).
    let selected: Bool?
    /// Whether the element is currently focused (`AXFocused`).
    let focused: Bool?
    /// Screen-space frame of the element. Encoded as `{x,y,width,height}` object.
    let frame: AXFrame?
    /// AX action names advertised by the element (e.g. `["AXPress"]`).
    let actions: [String]
    /// Total number of direct AX children (regardless of whether they are included).
    let childrenCount: Int
    /// Nested children, present only when `depth > 0` and not truncated.
    let children: [AXElementSnapshot]?
    /// `true` when the subtree was cut short by the depth or node cap.
    let truncated: Bool?

    enum CodingKeys: String, CodingKey {
        case id, role, subrole, title, label, value, description
        case enabled, selected, focused, frame, actions
        case childrenCount = "childrenCount"
        case children, truncated
    }
}

// MARK: - AXFrame

/// Screen-space rectangle, encoded as a plain JSON object.
struct AXFrame: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

// MARK: - Accessibility Error Codes

/// Stable, machine-readable error codes for the `accessibility` command domain.
enum AXErrorCode: String, Error {
    case permissionDenied   = "PERMISSION_DENIED_ACCESSIBILITY"
    case requiresPro        = "FEATURE_REQUIRES_PRO"
    case appNotFound        = "APP_NOT_FOUND"
    case windowNotFound     = "WINDOW_NOT_FOUND"
    case elementNotFound    = "ELEMENT_NOT_FOUND"
    case actionNotSupported = "ACTION_NOT_SUPPORTED"
    case valueNotSettable   = "VALUE_NOT_SETTABLE"
    case unsupportedTarget  = "UNSUPPORTED_TARGET"
    case treeTruncated      = "TREE_TRUNCATED"
    case internalError      = "INTERNAL_ERROR"
}

// MARK: - Result helpers

extension AXErrorCode {
    /// Build a structured error result dictionary.
    func result(message: String, command: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            "success": false,
            "errorCode": rawValue,
            "error": message,
        ]
        if let command { d["command"] = command }
        return d
    }
}

func axSuccess(_ data: [String: Any], command: String? = nil) -> [String: Any] {
    var d = data
    d["success"] = true
    if let command { d["command"] = command }
    return d
}
