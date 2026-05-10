import AppKit
import Foundation

enum JarvisOrbVisualStyle: String, CaseIterable, Identifiable {
    case ice
    case ember
    case nebula
    case aurora
    case mono

    static let storageKey = "jarvisTalkBackgroundOrbVisualStyleRaw"

    static var stored: JarvisOrbVisualStyle {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else {
            return .ice
        }
        return JarvisOrbVisualStyle(rawValue: raw) ?? .ice
    }

    var id: String { rawValue }

    var backdropNSCalibratedColor: NSColor {
        let rgb = backdropRGBComponents
        return NSColor(calibratedRed: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
    }

    /// Màu nền HTML + renderer (`#RRGGBB`).
    fileprivate var backdropHex: String {
        switch self {
        case .ice: "#050508"
        case .ember: "#0a0504"
        case .nebula: "#06040c"
        case .aurora: "#040a08"
        case .mono: "#050505"
        }
    }

    private var backdropRGBComponents: (r: Float, g: Float, b: Float) {
        switch self {
        case .ice: (5.0 / 255.0, 5.0 / 255.0, 8.0 / 255.0)
        case .ember: (10.0 / 255.0, 5.0 / 255.0, 4.0 / 255.0)
        case .nebula: (6.0 / 255.0, 4.0 / 255.0, 12.0 / 255.0)
        case .aurora: (4.0 / 255.0, 10.0 / 255.0, 8.0 / 255.0)
        case .mono: (5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0)
        }
    }

    /// Chuỗi JS gán `ORB_CFG`.
    fileprivate var webOrbConfigAssignment: String {
        switch self {
        case .ice:
            "const ORB_CFG = { bg: \"#050508\", base: \"#4ca8e8\", think: \"#6ec4ff\", speak: \"#5ab8f0\", electron: \"#ffffff\" };"
        case .ember:
            "const ORB_CFG = { bg: \"#0a0504\", base: \"#ff6b4a\", think: \"#ffb088\", speak: \"#ffd4a8\", electron: \"#fff5e6\" };"
        case .nebula:
            "const ORB_CFG = { bg: \"#06040c\", base: \"#a78bfa\", think: \"#c4b5fd\", speak: \"#e879f9\", electron: \"#f5f0ff\" };"
        case .aurora:
            "const ORB_CFG = { bg: \"#040a08\", base: \"#34d399\", think: \"#6ee7b7\", speak: \"#2dd4bf\", electron: \"#ecfdf5\" };"
        case .mono:
            "const ORB_CFG = { bg: \"#050505\", base: \"#9ca3af\", think: \"#d1d5db\", speak: \"#f3f4f6\", electron: \"#ffffff\" };"
        }
    }

    static func makeEmbeddedWebHTML(theme: JarvisOrbVisualStyle) -> String {
        JarvisOrbWebHTML.makeDocument(backgroundHex: theme.backdropHex, orbCfgLine: theme.webOrbConfigAssignment)
    }
}

// swiftlint:disable line_length type_body_length file_length

/// HTML WebGL orb (three.js CDN) parameterized by preset colors.
private enum JarvisOrbWebHTML {
    static func makeDocument(backgroundHex: String, orbCfgLine: String) -> String {
        let headCSS = headerAndCSS(backgroundHex: backgroundHex)
        let boot = orbBootstrapScript(orbCfgLine: orbCfgLine)
        return """
        <!doctype html>
        <html>
        \(headCSS)
        <body>
          <canvas id="orb-canvas"></canvas>
        \(boot)
        \(moduleScript)
          </script>
        </body>
        </html>
        """
    }

    private static func headerAndCSS(backgroundHex: String) -> String {
        """
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              overflow: hidden;
              background: \(backgroundHex);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            canvas {
              position: fixed;
              inset: 0;
              width: 100%;
              height: 100%;
              display: block;
            }
          </style>
        </head>
        """
    }

    private static func orbBootstrapScript(orbCfgLine: String) -> String {
        """
          <script>
            \(orbCfgLine)

            function orbHex(h) {
              return parseInt(h.slice(1), 16);
            }
          </script>
        """
    }

    private static let moduleScript = """
          <script type="module">
            import * as THREE from "https://unpkg.com/three@0.183.2/build/three.module.js";

            function orbHex(h) {
              return parseInt(h.slice(1), 16);
            }

            const canvas = document.getElementById("orb-canvas");
            const N = 2000;
            const MAX_LINES = 8000;
            let destroyed = false;
            let state = "idle";
            let externalLevel = 0;

            const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
            renderer.setPixelRatio(window.devicePixelRatio || 1);
            renderer.setSize(window.innerWidth, window.innerHeight);
            renderer.setClearColor(orbHex(ORB_CFG.bg), 1);

            const scene = new THREE.Scene();
            const camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 1, 1000);
            camera.position.z = 80;

            const geo = new THREE.BufferGeometry();
            const pos = new Float32Array(N * 3);
            const vel = new Float32Array(N * 3);
            const phase = new Float32Array(N);

            for (let i = 0; i < N; i++) {
              const theta = Math.random() * Math.PI * 2;
              const phi = Math.acos(2 * Math.random() - 1);
              const r = Math.pow(Math.random(), 0.5) * 25;
              pos[i * 3] = r * Math.sin(phi) * Math.cos(theta);
              pos[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
              pos[i * 3 + 2] = r * Math.cos(phi);
              phase[i] = Math.random() * 1000;
            }

            geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));

            const mat = new THREE.PointsMaterial({
              color: orbHex(ORB_CFG.base),
              size: 0.4,
              transparent: true,
              opacity: 0.6,
              sizeAttenuation: true,
              blending: THREE.AdditiveBlending,
              depthWrite: false,
            });
            const points = new THREE.Points(geo, mat);
            scene.add(points);

            const linePos = new Float32Array(MAX_LINES * 6);
            const lineGeo = new THREE.BufferGeometry();
            lineGeo.setAttribute("position", new THREE.BufferAttribute(linePos, 3));
            lineGeo.setDrawRange(0, 0);

            const lineMat = new THREE.LineBasicMaterial({
              color: orbHex(ORB_CFG.base),
              transparent: true,
              opacity: 0.0,
              blending: THREE.AdditiveBlending,
              depthWrite: false,
            });
            const lines = new THREE.LineSegments(lineGeo, lineMat);
            scene.add(lines);

            const MAX_ELECTRONS = 200;
            const electronGeo = new THREE.BufferGeometry();
            const electronPos = new Float32Array(MAX_ELECTRONS * 3);
            electronGeo.setAttribute("position", new THREE.BufferAttribute(electronPos, 3));
            electronGeo.setDrawRange(0, 0);

            const electronMat = new THREE.PointsMaterial({
              color: orbHex(ORB_CFG.electron),
              size: 0.8,
              transparent: true,
              opacity: 1.0,
              sizeAttenuation: true,
              blending: THREE.AdditiveBlending,
              depthWrite: false,
            });
            const electrons = new THREE.Points(electronGeo, electronMat);
            scene.add(electrons);

            const activeElectrons = [];
            let electronSpawnRate = 0;
            let targetElectronRate = 0;
            let lastElectronSpawn = 0;
            let activeConnections = [];

            let targetRadius = 25;
            let currentRadius = 25;
            let targetSpeed = 0.3;
            let currentSpeed = 0.3;
            let targetBright = 0.6;
            let currentBright = 0.6;
            let targetSize = 0.4;
            let currentSize = 0.4;
            let lineAmount = 0;
            let targetLineAmount = 0;
            const lineDistance = 8;

            let spinX = 0;
            let spinY = 0;
            let spinZ = 0;
            let transitionEnergy = 0;
            let lastState = "idle";
            let cloudZ = 0;
            let cloudZVel = 0;

            const clock = new THREE.Clock();

            function clamp01(value) {
              return Math.min(Math.max(Number(value) || 0, 0), 1);
            }

            window.setJarvisEnergyState = (nextState, level = 0) => {
              state = nextState || "idle";
              externalLevel = clamp01(level);
            };

            function levels(t) {
              if (state === "listening") {
                return { bass: externalLevel, mid: externalLevel * 0.8 };
              }
              if (state === "speaking") {
                return {
                  bass: Math.max(externalLevel, 0.12 + 0.16 * Math.max(0, Math.sin(t * 5.5))),
                  mid: 0.18 + 0.22 * Math.max(0, Math.sin(t * 8.0)),
                };
              }
              if (state === "thinking") {
                return {
                  bass: 0.04 + 0.04 * Math.max(0, Math.sin(t * 2.2)),
                  mid: 0.06,
                };
              }
              return { bass: 0, mid: 0 };
            }

            function animate() {
              if (destroyed) return;
              requestAnimationFrame(animate);
              const t = clock.getElapsedTime();

              switch (state) {
                case "idle":
                  targetRadius = 28; targetSpeed = 0.2; targetBright = 0.5; targetSize = 0.35;
                  targetLineAmount = 0.15; targetElectronRate = 0; break;
                case "listening":
                  targetRadius = 22; targetSpeed = 0.3; targetBright = 0.65; targetSize = 0.4;
                  targetLineAmount = 0.4; targetElectronRate = 0; break;
                case "thinking":
                  targetRadius = 16; targetSpeed = 0.5; targetBright = 0.7; targetSize = 0.3;
                  targetLineAmount = 1.0; targetElectronRate = 0.015; break;
                case "speaking":
                  targetRadius = 18; targetSpeed = 0.2; targetBright = 0.7; targetSize = 0.4;
                  targetLineAmount = 0.8; targetElectronRate = 0; break;
              }

              currentRadius += (targetRadius - currentRadius) * 0.02;
              currentSpeed += (targetSpeed - currentSpeed) * 0.02;
              currentBright += (targetBright - currentBright) * 0.02;
              currentSize += (targetSize - currentSize) * 0.02;
              lineAmount += (targetLineAmount - lineAmount) * 0.02;
              electronSpawnRate += (targetElectronRate - electronSpawnRate) * 0.02;

              if (state !== lastState) { transitionEnergy = 1.0; lastState = state; }
              transitionEnergy *= 0.985;
              if (transitionEnergy > 0.05) {
                spinX += transitionEnergy * 0.012 * Math.sin(t * 1.7);
                spinY += transitionEnergy * 0.015;
                spinZ += transitionEnergy * 0.008 * Math.cos(t * 1.3);
              }

              const { bass, mid } = levels(t);

              let zTarget = Math.sin(t * 0.12) * 8;
              if (state === "thinking") zTarget = Math.sin(t * 0.3) * 15 + Math.sin(t * 0.9) * 6;
              else if (state === "speaking") zTarget = Math.sin(t * 0.15) * 6 - bass * 10;
              cloudZVel += (zTarget - cloudZ) * 0.008;
              cloudZVel *= 0.94;
              cloudZ += cloudZVel;

              points.rotation.x = spinX; points.rotation.y = spinY; points.rotation.z = spinZ;
              points.position.z = cloudZ;
              lines.rotation.x = spinX; lines.rotation.y = spinY; lines.rotation.z = spinZ;
              lines.position.z = cloudZ;

              const p = geo.getAttribute("position");
              const a = p.array;

              for (let i = 0; i < N; i++) {
                const i3 = i * 3;
                const x = a[i3], y = a[i3 + 1], z = a[i3 + 2];
                const px = phase[i];

                vel[i3] += Math.sin(t * 0.05 + px) * 0.001 * currentSpeed;
                vel[i3 + 1] += Math.cos(t * 0.06 + px * 1.3) * 0.001 * currentSpeed;
                vel[i3 + 2] += Math.sin(t * 0.055 + px * 0.7) * 0.001 * currentSpeed;
                vel[i3] += Math.sin(t * 0.02 + px * 2.1 + y * 0.1) * 0.0008 * currentSpeed;
                vel[i3 + 1] += Math.cos(t * 0.025 + px * 1.7 + z * 0.1) * 0.0008 * currentSpeed;
                vel[i3 + 2] += Math.sin(t * 0.022 + px * 0.9 + x * 0.1) * 0.0008 * currentSpeed;

                const dist = Math.sqrt(x * x + y * y + z * z) || 0.01;
                const pull = Math.max(0, dist - currentRadius) * 0.002 + 0.0003;
                vel[i3] -= (x / dist) * pull;
                vel[i3 + 1] -= (y / dist) * pull;
                vel[i3 + 2] -= (z / dist) * pull;

                if (bass > 0.05) {
                  vel[i3] += (x / dist) * bass * 0.02;
                  vel[i3 + 1] += (y / dist) * bass * 0.02;
                  vel[i3 + 2] += (z / dist) * bass * 0.02;
                }
                if (state === "speaking" && mid > 0.1) {
                  const pulse = Math.sin(t * 8 + px);
                  vel[i3] += (x / dist) * mid * 0.012 * pulse;
                  vel[i3 + 1] += (y / dist) * mid * 0.012 * pulse;
                }

                vel[i3] *= 0.992; vel[i3 + 1] *= 0.992; vel[i3 + 2] *= 0.992;
                a[i3] += vel[i3]; a[i3 + 1] += vel[i3 + 1]; a[i3 + 2] += vel[i3 + 2];
              }
              p.needsUpdate = true;

              if (lineAmount > 0.01) {
                const lp = lineGeo.getAttribute("position");
                const la = lp.array;
                let lineCount = 0;
                const maxDist = lineDistance * (1 + bass * 0.5);
                const maxDistSq = maxDist * maxDist;
                const step = Math.max(1, Math.floor(N / 600));

                for (let i = 0; i < N && lineCount < MAX_LINES; i += step) {
                  const i3 = i * 3;
                  const x1 = a[i3], y1 = a[i3 + 1], z1 = a[i3 + 2];
                  for (let j = i + step; j < N && lineCount < MAX_LINES; j += step) {
                    const j3 = j * 3;
                    const dx = a[j3] - x1, dy = a[j3 + 1] - y1, dz = a[j3 + 2] - z1;
                    if (dx * dx + dy * dy + dz * dz < maxDistSq) {
                      const idx = lineCount * 6;
                      la[idx] = x1; la[idx + 1] = y1; la[idx + 2] = z1;
                      la[idx + 3] = a[j3]; la[idx + 4] = a[j3 + 1]; la[idx + 5] = a[j3 + 2];
                      lineCount++;
                    }
                  }
                }
                lineGeo.setDrawRange(0, lineCount * 2);
                lp.needsUpdate = true;
                lineMat.opacity = lineAmount * 0.12;

                activeConnections = [];
                for (let c = 0; c < Math.min(lineCount, 500); c++) {
                  const ci = c * 6;
                  activeConnections.push({
                    x1: la[ci], y1: la[ci + 1], z1: la[ci + 2],
                    x2: la[ci + 3], y2: la[ci + 4], z2: la[ci + 5],
                  });
                }
              } else {
                lineGeo.setDrawRange(0, 0);
                activeConnections = [];
              }

              if (activeConnections.length > 0 && electronSpawnRate > 0.005) {
                if (activeElectrons.length < 3 && (t - lastElectronSpawn) > 1.0) {
                  const conn = activeConnections[Math.floor(Math.random() * activeConnections.length)];
                  activeElectrons.push({
                    sx: conn.x1, sy: conn.y1, sz: conn.z1,
                    ex: conn.x2, ey: conn.y2, ez: conn.z2,
                    t: 0,
                    speed: 0.003 + Math.random() * 0.003,
                  });
                  lastElectronSpawn = t;
                }
              }

              const ep = electronGeo.getAttribute("position");
              const ea = ep.array;
              let aliveCount = 0;
              for (let e = activeElectrons.length - 1; e >= 0; e--) {
                const el = activeElectrons[e];
                el.t += el.speed;
                if (el.t >= 1) {
                  activeElectrons.splice(e, 1);
                  continue;
                }
                const ei = aliveCount * 3;
                ea[ei] = el.sx + (el.ex - el.sx) * el.t;
                ea[ei + 1] = el.sy + (el.ey - el.sy) * el.t;
                ea[ei + 2] = el.sz + (el.ez - el.sz) * el.t;
                aliveCount++;
              }
              electronGeo.setDrawRange(0, aliveCount);
              ep.needsUpdate = true;
              electrons.rotation.x = spinX; electrons.rotation.y = spinY; electrons.rotation.z = spinZ;
              electrons.position.z = cloudZ;

              mat.opacity = currentBright + bass * 0.08;
              mat.size = currentSize + bass * 0.05;

              if (state === "thinking") {
                mat.color.lerp(new THREE.Color(orbHex(ORB_CFG.think)), 0.015);
                lineMat.color.lerp(new THREE.Color(orbHex(ORB_CFG.think)), 0.015);
              } else if (state === "speaking") {
                mat.color.lerp(new THREE.Color(orbHex(ORB_CFG.speak)), 0.015);
                lineMat.color.lerp(new THREE.Color(orbHex(ORB_CFG.speak)), 0.015);
              } else {
                mat.color.lerp(new THREE.Color(orbHex(ORB_CFG.base)), 0.015);
                lineMat.color.lerp(new THREE.Color(orbHex(ORB_CFG.base)), 0.015);
              }

              electronMat.color.lerp(new THREE.Color(orbHex(ORB_CFG.electron)), 0.05);

              camera.position.x = Math.sin(t * 0.02) * 5;
              camera.position.y = Math.cos(t * 0.03) * 3;
              camera.lookAt(0, 0, cloudZ * 0.2);

              renderer.render(scene, camera);
            }

            function onResize() {
              camera.aspect = window.innerWidth / window.innerHeight;
              camera.updateProjectionMatrix();
              renderer.setSize(window.innerWidth, window.innerHeight);
            }

            window.addEventListener("resize", onResize);
            animate();
    """
}
