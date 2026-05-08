import AppKit
import SwiftUI

@MainActor
public final class SpotlightTestWindowController {
    public static let shared = SpotlightTestWindowController()
    
    private var window: NSWindow?
    
    public init() {}
    
    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let view = SpotlightTestView()
        let controller = NSHostingController(rootView: view)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "Spotlight Search Test (Debug)"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
