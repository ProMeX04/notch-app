import AppKit
import QuartzCore
import simd
import WebKit

enum JarvisEnergyState {
    case idle
    case listening
    case thinking
    case speaking
}

private extension JarvisEnergyState {
    var webName: String {
        switch self {
        case .idle: "idle"
        case .listening: "listening"
        case .thinking: "thinking"
        case .speaking: "speaking"
        }
    }
}

/// WKWebView mặc định trả `mouseDownCanMoveWindow == false` nên không kéo được cửa sổ có `movableByWindowBackground`.
private final class JarvisOrbWKWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = JarvisOrbContextMenu.makeOrbMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

@MainActor
final class JarvisBackgroundView: NSView, WKNavigationDelegate {
    private struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        let phase: Float
    }

    private struct Connection {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
    }

    private struct Electron {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        var progress: Float
        let speed: Float
    }

    private struct CameraView {
        let position: SIMD3<Float>
        let right: SIMD3<Float>
        let up: SIMD3<Float>
        let forward: SIMD3<Float>
        let focalLength: Float
        let pointScale: Float
    }

    private struct ProjectedPoint {
        let point: CGPoint
        let depthScale: Float
    }

    private let particleCount = 2_000
    private let maxLineCount = 8_000
    private let maxStoredConnections = 500
    private var particles: [Particle] = []
    private var activeConnections: [Connection] = []
    private var electrons: [Electron] = []
    private var activeDisplayLink: CADisplayLink?
    private var webView: WKWebView?
    private var orbWebLoadThemeCommitted: JarvisOrbVisualStyle?
    private var orbHTMLThemeQueued: JarvisOrbVisualStyle?
    private var activeState: JarvisEnergyState = .idle
    private var lastState: JarvisEnergyState = .idle
    private var signalLevel: Float = 0
    private var targetRadius: Float = 25
    private var currentRadius: Float = 25
    private var targetSpeed: Float = 0.3
    private var currentSpeed: Float = 0.3
    private var targetBrightness: Float = 0.6
    private var currentBrightness: Float = 0.6
    private var targetPointSize: Float = 0.4
    private var currentPointSize: Float = 0.4
    private var targetLineAmount: Float = 0
    private var lineAmount: Float = 0
    private var targetElectronRate: Float = 0
    private var electronSpawnRate: Float = 0
    private var transitionEnergy: Float = 0
    private var spin = SIMD3<Float>(repeating: 0)
    private var cloudZ: Float = 0
    private var cloudZVelocity: Float = 0
    private var lastElectronSpawnTime: Float = 0
    private var currentColor = SIMD3<Float>(76.0 / 255.0, 168.0 / 255.0, 232.0 / 255.0)
    private let startDate = Date()

    override var isOpaque: Bool { true }

    /// Cho phép kéo cửa sổ qua view khi không dùng web (fallback vẽ AppKit).
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimating()
        } else {
            syncWebOrbState()
        }
    }

    func setEnergyState(_ state: JarvisEnergyState, signalLevel: Double) {
        activeState = state
        self.signalLevel = Float(min(max(signalLevel, 0), 1))
        syncWebOrbState()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        jarvisBackdropFillColor.setFill()
        bounds.fill()

        guard webView == nil else { return }

        let time = Float(Date().timeIntervalSince(startDate))
        updateStateTargets(time: time)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let camera = makeCameraView(time: time)
        var projectedPoints: [ProjectedPoint] = []
        projectedPoints.reserveCapacity(particles.count)

        for index in particles.indices {
            updateParticle(at: index, time: time)
            let rotated = rotate(particles[index].position + SIMD3<Float>(0, 0, cloudZ), spin: spin)
            projectedPoints.append(project(rotated, center: center, camera: camera))
        }

        drawParticles(in: context, points: projectedPoints, time: time)
        drawLines(in: context, projectedPoints: projectedPoints)
        updateElectrons(time: time)
        drawElectrons(in: context, scale: camera, center: center)
    }

    private func commonInit() {
        wantsLayer = true
        refreshBackdropLayerFromTheme()
        particles = makeParticles()
        installWebOrb()
    }

    private func refreshBackdropLayerFromTheme() {
        layer?.backgroundColor = JarvisOrbVisualStyle.stored.backdropNSCalibratedColor.cgColor
    }

    private func installWebOrb() {
        guard webView == nil else { return }

        let theme = JarvisOrbVisualStyle.stored
        orbHTMLThemeQueued = theme

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = JarvisOrbWKWebView(frame: bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.isHidden = false
        addSubview(webView)

        self.webView = webView
        webView.loadHTMLString(
            JarvisOrbVisualStyle.makeEmbeddedWebHTML(theme: theme),
            baseURL: URL(string: "https://localhost/")
        )
    }

    /// Gọi khi preset orb trong UserDefaults đổi trong lúc cửa sổ đang hiện (`WKWebView` đã tạo).
    func reloadOrbEmbeddedWebIfStoredPresetChanged() {
        guard webView != nil else { return }
        let desired = JarvisOrbVisualStyle.stored
        if orbWebLoadThemeCommitted == desired { return }
        if orbWebLoadThemeCommitted == nil, orbHTMLThemeQueued == desired { return }
        webView?.removeFromSuperview()
        webView = nil
        orbWebLoadThemeCommitted = nil
        orbHTMLThemeQueued = nil
        installWebOrb()
        refreshBackdropLayerFromTheme()
        syncWebOrbState()
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if let queued = orbHTMLThemeQueued {
                orbWebLoadThemeCommitted = queued
                orbHTMLThemeQueued = nil
            }
            self.syncWebOrbState()
        }
    }

    private func syncWebOrbState() {
        guard let webView else { return }
        let script = "window.setJarvisEnergyState && window.setJarvisEnergyState('\(activeState.webName)', \(Double(signalLevel)));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func startAnimating() {
        guard activeDisplayLink == nil else { return }

        let displayLink = self.displayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 45)
        displayLink.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        activeDisplayLink = displayLink
    }

    private func stopAnimating() {
        activeDisplayLink?.invalidate()
        activeDisplayLink = nil
    }

    @objc
    private func displayLinkDidFire() {
        needsDisplay = true
    }

    private func makeParticles() -> [Particle] {
        (0..<particleCount).map { _ in
            let theta = Float.random(in: 0..<(Float.pi * 2))
            let phi = acos(Float.random(in: -1...1))
            let radius = sqrt(Float.random(in: 0...1)) * 25
            let position = SIMD3<Float>(
                radius * sin(phi) * cos(theta),
                radius * sin(phi) * sin(theta),
                radius * cos(phi)
            )
            return Particle(
                position: position,
                velocity: .zero,
                phase: Float.random(in: 0...1_000)
            )
        }
    }

    private func updateStateTargets(time: Float) {
        switch activeState {
        case .idle:
            targetRadius = 28
            targetSpeed = 0.2
            targetBrightness = 0.5
            targetPointSize = 0.35
            targetLineAmount = 0.15
            targetElectronRate = 0
        case .listening:
            targetRadius = 22
            targetSpeed = 0.3
            targetBrightness = 0.65
            targetPointSize = 0.4
            targetLineAmount = 0.4
            targetElectronRate = 0
        case .thinking:
            targetRadius = 16
            targetSpeed = 0.5
            targetBrightness = 0.7
            targetPointSize = 0.3
            targetLineAmount = 1.0
            targetElectronRate = 0.015
        case .speaking:
            targetRadius = 18
            targetSpeed = 0.2
            targetBrightness = 0.7
            targetPointSize = 0.4
            targetLineAmount = 0.8
            targetElectronRate = 0
        }

        currentRadius += (targetRadius - currentRadius) * 0.02
        currentSpeed += (targetSpeed - currentSpeed) * 0.02
        currentBrightness += (targetBrightness - currentBrightness) * 0.02
        currentPointSize += (targetPointSize - currentPointSize) * 0.02
        lineAmount += (targetLineAmount - lineAmount) * 0.02
        electronSpawnRate += (targetElectronRate - electronSpawnRate) * 0.02
        currentColor += (Self.jarvisColorVector(for: activeState) - currentColor) * 0.015

        if activeState != lastState {
            transitionEnergy = 1
            lastState = activeState
        }
        transitionEnergy *= 0.985
        if transitionEnergy > 0.05 {
            spin.x += transitionEnergy * 0.012 * sin(time * 1.7)
            spin.y += transitionEnergy * 0.015
            spin.z += transitionEnergy * 0.008 * cos(time * 1.3)
        }

        let bass = bassLevel(time: time)
        var zTarget = sin(time * 0.12) * 8
        if activeState == .thinking {
            zTarget = sin(time * 0.3) * 15 + sin(time * 0.9) * 6
        } else if activeState == .speaking {
            zTarget = sin(time * 0.15) * 6 - bass * 10
        }
        cloudZVelocity += (zTarget - cloudZ) * 0.008
        cloudZVelocity *= 0.94
        cloudZ += cloudZVelocity
    }

    private func updateParticle(at index: Int, time: Float) {
        let phase = particles[index].phase
        let position = particles[index].position
        var velocity = particles[index].velocity
        let bass = bassLevel(time: time)
        let mid = midLevel(time: time)

        velocity.x += sin(time * 0.05 + phase) * 0.001 * currentSpeed
        velocity.y += cos(time * 0.06 + phase * 1.3) * 0.001 * currentSpeed
        velocity.z += sin(time * 0.055 + phase * 0.7) * 0.001 * currentSpeed
        velocity.x += sin(time * 0.02 + phase * 2.1 + position.y * 0.1) * 0.0008 * currentSpeed
        velocity.y += cos(time * 0.025 + phase * 1.7 + position.z * 0.1) * 0.0008 * currentSpeed
        velocity.z += sin(time * 0.022 + phase * 0.9 + position.x * 0.1) * 0.0008 * currentSpeed

        let distance = max(simd_length(position), 0.01)
        let normal = position / distance
        let pull = max(0, distance - currentRadius) * 0.002 + 0.0003
        velocity -= normal * pull

        if bass > 0.05 {
            velocity += normal * bass * 0.02
        }
        if activeState == .speaking && mid > 0.1 {
            let pulse = sin(time * 8 + phase)
            velocity.x += normal.x * mid * 0.012 * pulse
            velocity.y += normal.y * mid * 0.012 * pulse
        }

        velocity *= 0.992
        particles[index].velocity = velocity
        particles[index].position += velocity
    }

    private func drawLines(in context: CGContext, projectedPoints: [ProjectedPoint]) {
        guard lineAmount > 0.01 else {
            activeConnections.removeAll()
            return
        }

        let bass = CGFloat(bassLevel(time: Float(Date().timeIntervalSince(startDate))))
        let maxDistance = CGFloat(8) * (1 + bass * 0.5)
        let maxDistanceSquared = Float(maxDistance * maxDistance)
        let step = max(1, particleCount / 600)
        var lineCount = 0
        activeConnections.removeAll(keepingCapacity: true)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setStrokeColor(jarvisColor(alpha: CGFloat(lineAmount) * 0.12).cgColor)
        context.setLineWidth(1.0)
        context.beginPath()

        var i = 0
        while i < particles.count && lineCount < maxLineCount {
            var j = i + step
            let p1 = particles[i].position
            while j < particles.count && lineCount < maxLineCount {
                let p2 = particles[j].position
                if simd_length_squared(p2 - p1) < maxDistanceSquared {
                    context.move(to: projectedPoints[i].point)
                    context.addLine(to: projectedPoints[j].point)
                    if activeConnections.count < maxStoredConnections {
                        activeConnections.append(Connection(start: p1, end: p2))
                    }
                    lineCount += 1
                }
                j += step
            }
            i += step
        }

        context.strokePath()
        context.restoreGState()
    }

    private func updateElectrons(time: Float) {
        if !activeConnections.isEmpty && electronSpawnRate > 0.005 {
            if electrons.count < 3, time - lastElectronSpawnTime > 1.0, let connection = activeConnections.randomElement() {
                electrons.append(Electron(
                    start: connection.start,
                    end: connection.end,
                    progress: 0,
                    speed: Float.random(in: 0.003...0.006)
                ))
                lastElectronSpawnTime = time
            }
        }

        for index in electrons.indices.reversed() {
            electrons[index].progress += electrons[index].speed
            if electrons[index].progress >= 1 {
                electrons.remove(at: index)
            }
        }
    }

    private func drawElectrons(in context: CGContext, scale camera: CameraView, center: CGPoint) {
        guard !electrons.isEmpty else { return }

        context.saveGState()
        context.setBlendMode(.plusLighter)
        for electron in electrons {
            context.setFillColor(NSColor.white.cgColor)
            let point3D = mix(electron.start, electron.end, t: electron.progress)
            let rotated = rotate(point3D + SIMD3<Float>(0, 0, cloudZ), spin: spin)
            let projected = project(rotated, center: center, camera: camera)
            let point = projected.point
            let size = CGFloat(0.8 * projected.depthScale)
            context.fill(CGRect(
                x: point.x - size / 2,
                y: point.y - size / 2,
                width: size,
                height: size
            ))
        }
        context.restoreGState()
    }

    private func drawParticles(in context: CGContext, points: [ProjectedPoint], time: Float) {
        let bass = bassLevel(time: time)
        let alpha = CGFloat(min(max(currentBrightness + bass * 0.08, 0), 1))
        let coreColor = jarvisColor(alpha: alpha)
        let materialSize = currentPointSize + bass * 0.05

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setFillColor(coreColor.cgColor)
        for projected in points {
            let point = projected.point
            let size = CGFloat(materialSize * projected.depthScale)
            context.fill(CGRect(
                x: point.x - size / 2,
                y: point.y - size / 2,
                width: size,
                height: size
            ))
        }
        context.restoreGState()
    }

    private func makeCameraView(time: Float) -> CameraView {
        let cameraPosition = SIMD3<Float>(
            sin(time * 0.02) * 5,
            cos(time * 0.03) * 3,
            80
        )
        let target = SIMD3<Float>(0, 0, cloudZ * 0.2)
        let forward = simd_normalize(target - cameraPosition)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let focalLength = Float(bounds.height) / (2 * tan(Float.pi / 8))
        let pointScale = Float(bounds.height) * 0.5
        return CameraView(
            position: cameraPosition,
            right: right,
            up: up,
            forward: forward,
            focalLength: focalLength,
            pointScale: pointScale
        )
    }

    private func project(_ point: SIMD3<Float>, center: CGPoint, camera: CameraView) -> ProjectedPoint {
        let relative = point - camera.position
        let x = simd_dot(relative, camera.right)
        let y = simd_dot(relative, camera.up)
        let depth = max(1, simd_dot(relative, camera.forward))
        let screenScale = camera.focalLength / depth
        let depthScale = camera.pointScale / depth
        return ProjectedPoint(
            point: CGPoint(
                x: center.x + CGFloat(x * screenScale),
                y: center.y + CGFloat(y * screenScale)
            ),
            depthScale: depthScale
        )
    }

    private func rotate(_ point: SIMD3<Float>, spin: SIMD3<Float>) -> SIMD3<Float> {
        let cx = cos(spin.x)
        let sx = sin(spin.x)
        let cy = cos(spin.y)
        let sy = sin(spin.y)
        let cz = cos(spin.z)
        let sz = sin(spin.z)

        var rotated = SIMD3<Float>(
            point.x,
            point.y * cx - point.z * sx,
            point.y * sx + point.z * cx
        )
        rotated = SIMD3<Float>(
            rotated.x * cy - rotated.z * sy,
            rotated.y,
            rotated.x * sy + rotated.z * cy
        )
        return SIMD3<Float>(
            rotated.x * cz - rotated.y * sz,
            rotated.x * sz + rotated.y * cz,
            rotated.z
        )
    }

    private func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * t
    }

    private func bassLevel(time: Float) -> Float {
        min(max(signalLevel, 0), 1)
    }

    private func midLevel(time: Float) -> Float {
        min(max(signalLevel * 0.8, 0), 1)
    }

    /// Khớp bảng màu trong jarvis/frontend/src/orb.ts (PointsMaterial / LineBasicMaterial lerp theo state).
    private static func jarvisColorVector(for state: JarvisEnergyState) -> SIMD3<Float> {
        switch state {
        case .idle, .listening:
            return SIMD3<Float>(76.0 / 255.0, 168.0 / 255.0, 232.0 / 255.0)
        case .thinking:
            return SIMD3<Float>(110.0 / 255.0, 196.0 / 255.0, 1.0)
        case .speaking:
            return SIMD3<Float>(90.0 / 255.0, 184.0 / 255.0, 240.0 / 255.0)
        }
    }

    private var jarvisBackdropFillColor: NSColor { JarvisOrbVisualStyle.stored.backdropNSCalibratedColor }

    private func jarvisColor(alpha: CGFloat) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(currentColor.x),
            green: CGFloat(currentColor.y),
            blue: CGFloat(currentColor.z),
            alpha: alpha
        )
    }

}
