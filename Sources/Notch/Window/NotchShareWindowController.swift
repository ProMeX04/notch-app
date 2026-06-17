import AppKit
import SwiftUI
import NotchShelfFeature

@MainActor
public final class NotchShareWindowController: NSObject, NSWindowDelegate {
    public static let shared = NotchShareWindowController()
    
    private var window: NSWindow?
    private var item: NotchShelfItem?
    
    public func showSharePanel(for item: NotchShelfItem, portalBaseURL: URL) {
        self.item = item
        
        if let window = window {
            if let hostingController = window.contentViewController as? NSHostingController<GoogleDriveShareView> {
                hostingController.rootView = GoogleDriveShareView(item: item, portalBaseURL: portalBaseURL, onClose: { [weak self] in
                    self?.close()
                })
            }
            window.title = "Share \"\(item.displayName)\""
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let shareView = GoogleDriveShareView(item: item, portalBaseURL: portalBaseURL, onClose: { [weak self] in
            self?.close()
        })
        
        let hostingController = NSHostingController(rootView: shareView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Share \"\(item.displayName)\""
        newWindow.setContentSize(NSSize(width: 480, height: 480))
        newWindow.minSize = NSSize(width: 480, height: 480)
        newWindow.maxSize = NSSize(width: 480, height: 480)
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = newWindow
    }
    
    public func close() {
        window?.close()
        window = nil
        item = nil
    }
    
    public func windowWillClose(_ notification: Notification) {
        window = nil
        item = nil
    }
}
