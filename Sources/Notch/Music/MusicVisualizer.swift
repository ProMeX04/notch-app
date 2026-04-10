import AppKit
import QuartzCore
import SwiftUI

final class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying = false
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for index in 0..<barCount {
            let xPosition = CGFloat(index) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + (barWidth / 2), y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            barLayer.path = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                cornerWidth: barWidth / 2,
                cornerHeight: barWidth / 2,
                transform: nil
            )
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBars()
            }
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (index, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[index]
            let targetScale = CGFloat.random(in: 0.35...1.0)
            barScales[index] = targetScale

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false

            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }

            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[index] = 0.35
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing

        if isPlaying && !isHiddenOrHasHiddenAncestor {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil || isHiddenOrHasHiddenAncestor {
            stopAnimating()
        } else if isPlaying {
            startAnimating()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        
        if superview == nil || isHiddenOrHasHiddenAncestor {
            stopAnimating()
        } else if isPlaying {
            startAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}
