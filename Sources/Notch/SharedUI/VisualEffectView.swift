import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var cornerRadius: CGFloat = 16

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.wantsLayer = true
        updateVisualEffectView(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        updateVisualEffectView(nsView)
    }

    private func updateVisualEffectView(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
