import Foundation

/// Three.js orb: particle sphere + custom shaders (Particle Wave Edition), bridged via `window.setJarvisEnergyState`.
/// Nền WebGL trong suốt; vùng đen là **bao lồi 2D** (màn hình) của đám hạt sau dịch chuyển — không phải đĩa/cầu cố định.
enum JarvisOrbParticleWaveHTML {
    static func makeDocument() -> String {
        """
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              overflow: hidden;
              width: 100%;
              height: 100%;
              background: transparent;
            }
            #canvas-container {
              position: fixed;
              inset: 0;
              z-index: 1;
            }
          </style>
          <script type="module">
            import * as THREE from "https://unpkg.com/three@0.183.2/build/three.module.js";

            const container = document.getElementById("canvas-container");

            let scene, camera, renderer, orbGroup, hullBackdropMesh, particles;
            const clock = new THREE.Clock();

            /** Trùng với khối `snoise` trong `vertexShader` (float32-ish / same ops as GLSL). */
            function mod289f(t) {
              return t - Math.floor(t * (1 / 289)) * 289;
            }

            function mod289v3(ix, iy, iz) {
              return [mod289f(ix), mod289f(iy), mod289f(iz)];
            }

            function mod289v4(x, y, z, w) {
              return [mod289f(x), mod289f(y), mod289f(z), mod289f(w)];
            }

            function permuteVec4(v) {
              return mod289v4(
                (v[0] * 34 + 1) * v[0],
                (v[1] * 34 + 1) * v[1],
                (v[2] * 34 + 1) * v[2],
                (v[3] * 34 + 1) * v[3]
              );
            }

            function vec4sum(a, b) {
              return [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]];
            }

            function stepGE(edge, x) {
              return x >= edge ? 1 : 0;
            }

            function dot3(ax, ay, az, bx, by, bz) {
              return ax * bx + ay * by + az * bz;
            }

            function taylorInvSqrt4(rx, ry, rz, rw) {
              const c = 1.79284291400159;
              const k = 0.85373472095314;
              return [c - k * rx, c - k * ry, c - k * rz, c - k * rw];
            }

            function shaderSnoise3(vx, vy, vz) {
              const Cx = 1 / 6;
              const Cy = 1 / 3;
              const vdot = (vx + vy + vz) * Cy;
              let ix = Math.floor(vx + vdot);
              let iy = Math.floor(vy + vdot);
              let iz = Math.floor(vz + vdot);
              const idot6 = (ix + iy + iz) * Cx;
              const x0x = vx - ix + idot6;
              const x0y = vy - iy + idot6;
              const x0z = vz - iz + idot6;

              const gx = stepGE(x0y, x0x);
              const gy = stepGE(x0z, x0y);
              const gz = stepGE(x0x, x0z);

              let i1x = Math.min(gx, 1 - gz);
              let i1y = Math.min(gy, 1 - gx);
              let i1z = Math.min(gz, 1 - gy);

              let i2x = Math.max(gx, 1 - gz);
              let i2y = Math.max(gy, 1 - gx);
              let i2z = Math.max(gz, 1 - gy);

              const x1x = x0x - i1x + Cx;
              const x1y = x0y - i1y + Cx;
              const x1z = x0z - i1z + Cx;

              const x2x = x0x - i2x + Cy;
              const x2y = x0y - i2y + Cy;
              const x2z = x0z - i2z + Cy;

              const x3x = x0x - 0.5;
              const x3y = x0y - 0.5;
              const x3z = x0z - 0.5;

              const mi = mod289v3(ix, iy, iz);
              ix = mi[0];
              iy = mi[1];
              iz = mi[2];

              const qa = [iz + 0, iz + i1z, iz + i2z, iz + 1];
              const pa = permuteVec4(qa);
              const qb = vec4sum(pa, [iy + 0, iy + i1y, iy + i2y, iy + 1]);
              const pb = permuteVec4(qb);
              const qc = vec4sum(pb, [ix + 0, ix + i1x, ix + i2x, ix + 1]);
              const pj = permuteVec4(qc);

              const n_ = 1 / 7;
              const nsx = n_ * 2;
              const nsy = n_ * 0.5 - 1;
              const nsz = n_;

              const j0 = pj[0] - 49 * Math.floor(pj[0] * nsz * nsz);
              const j1 = pj[1] - 49 * Math.floor(pj[1] * nsz * nsz);
              const j2 = pj[2] - 49 * Math.floor(pj[2] * nsz * nsz);
              const j3 = pj[3] - 49 * Math.floor(pj[3] * nsz * nsz);

              const xd0 = Math.floor(j0 * nsz);
              const xd1 = Math.floor(j1 * nsz);
              const xd2 = Math.floor(j2 * nsz);
              const xd3 = Math.floor(j3 * nsz);

              const yd0 = Math.floor(j0 - 7 * xd0);
              const yd1 = Math.floor(j1 - 7 * xd1);
              const yd2 = Math.floor(j2 - 7 * xd2);
              const yd3 = Math.floor(j3 - 7 * xd3);

              const xv0 = xd0 * nsx + nsy;
              const xv1 = xd1 * nsx + nsy;
              const xv2 = xd2 * nsx + nsy;
              const xv3 = xd3 * nsx + nsy;

              const yv0 = yd0 * nsx + nsy;
              const yv1 = yd1 * nsx + nsy;
              const yv2 = yd2 * nsx + nsy;
              const yv3 = yd3 * nsx + nsy;

              const hx0 = 1 - Math.abs(xv0) - Math.abs(yv0);
              const hx1 = 1 - Math.abs(xv1) - Math.abs(yv1);
              const hx2 = 1 - Math.abs(xv2) - Math.abs(yv2);
              const hx3 = 1 - Math.abs(xv3) - Math.abs(yv3);

              const b0 = [xv0, xv1, yv0, yv1];
              const b1 = [xv2, xv3, yv2, yv3];

              const s0 = [
                Math.floor(b0[0]) * 2 + 1,
                Math.floor(b0[1]) * 2 + 1,
                Math.floor(b0[2]) * 2 + 1,
                Math.floor(b0[3]) * 2 + 1
              ];
              const s1 = [
                Math.floor(b1[0]) * 2 + 1,
                Math.floor(b1[1]) * 2 + 1,
                Math.floor(b1[2]) * 2 + 1,
                Math.floor(b1[3]) * 2 + 1
              ];

              const sh0 = hx0 <= 0 ? -1 : 0;
              const sh1 = hx1 <= 0 ? -1 : 0;
              const sh2 = hx2 <= 0 ? -1 : 0;
              const sh3 = hx3 <= 0 ? -1 : 0;

              const a0 = [
                b0[0] + s0[0] * sh0,
                b0[2] + s0[2] * sh0,
                b0[1] + s0[1] * sh1,
                b0[3] + s0[3] * sh1
              ];
              const a1 = [
                b1[0] + s1[0] * sh2,
                b1[2] + s1[2] * sh2,
                b1[1] + s1[1] * sh3,
                b1[3] + s1[3] * sh3
              ];

              let p0x = a0[0];
              let p0y = a0[1];
              let p0z = hx0;
              let p1x = a0[2];
              let p1y = a0[3];
              let p1z = hx1;
              let p2x = a1[0];
              let p2y = a1[1];
              let p2z = hx2;
              let p3x = a1[2];
              let p3y = a1[3];
              let p3z = hx3;

              const tIn = taylorInvSqrt4(
                dot3(p0x, p0y, p0z, p0x, p0y, p0z),
                dot3(p1x, p1y, p1z, p1x, p1y, p1z),
                dot3(p2x, p2y, p2z, p2x, p2y, p2z),
                dot3(p3x, p3y, p3z, p3x, p3y, p3z)
              );
              p0x *= tIn[0];
              p0y *= tIn[0];
              p0z *= tIn[0];
              p1x *= tIn[1];
              p1y *= tIn[1];
              p1z *= tIn[1];
              p2x *= tIn[2];
              p2y *= tIn[2];
              p2z *= tIn[2];
              p3x *= tIn[3];
              p3y *= tIn[3];
              p3z *= tIn[3];

              const d0 = Math.max(0.6 - dot3(x0x, x0y, x0z, x0x, x0y, x0z), 0);
              const d1 = Math.max(0.6 - dot3(x1x, x1y, x1z, x1x, x1y, x1z), 0);
              const d2 = Math.max(0.6 - dot3(x2x, x2y, x2z, x2x, x2y, x2z), 0);
              const d3 = Math.max(0.6 - dot3(x3x, x3y, x3z, x3x, x3y, x3z), 0);

              const m0 = d0 * d0;
              const m1 = d1 * d1;
              const m2 = d2 * d2;
              const m3 = d3 * d3;

              return (
                42 *
                (m0 * m0 * dot3(p0x, p0y, p0z, x0x, x0y, x0z) +
                  m1 * m1 * dot3(p1x, p1y, p1z, x1x, x1y, x1z) +
                  m2 * m2 * dot3(p2x, p2y, p2z, x2x, x2y, x2z) +
                  m3 * m3 * dot3(p3x, p3y, p3z, x3x, x3y, x3z))
              );
            }

            let externalLevel = 0;
            /** Theo dõi mức tín hiệu mượt; tránh giật rotation/pulse khi RMS nhảy. */
            let smoothedExternalLevel = 0;
            /** Envelope CPU (additive nhỏ). Nhịp chính khi speaking dùng `uSpeechDrive` trong vertex shader. */
            let speakingEnvelope = 0;
            /** Bám speaking nhanh; nhịp thở chạy hoàn toàn trong shader theo `uTime`. */
            let speechDrive = 0;

            function clamp01(v) {
              const x = Number(v);
              return Math.min(Math.max(Number.isFinite(x) ? x : 0, 0), 1);
            }

            /** Nguyên tắc phân biệt 4 trạng thái: idle = chậm/trầm/ít dải; listening = sáng + pulse nhanh + hạt to hơn; thinking = tím–mint + noise dày + ribbon nhanh; speaking = ấm + phồng chậm, phản ứng RMS riêng. */
            const STATES = {
              idle: {
                color1: new THREE.Color("#0a1a6e"),
                color2: new THREE.Color("#2ec8ff"),
                speed: 0.034,
                amplitude: 0.021,
                frequency: 0.155,
                pulse: 0.0
              },
              listening: {
                color1: new THREE.Color("#00a8ff"),
                color2: new THREE.Color("#8ec5ff"),
                speed: 0.128,
                amplitude: 0.05,
                frequency: 0.35,
                pulse: 0.016
              },
              thinking: {
                color1: new THREE.Color("#3a2080"),
                color2: new THREE.Color("#3cffc5"),
                speed: 0.29,
                amplitude: 0.102,
                frequency: 0.52,
                pulse: 0.005
              },
              speaking: {
                color1: new THREE.Color("#5b7cff"),
                color2: new THREE.Color("#dcf6ff"),
                speed: 0.05,
                amplitude: 0.042,
                frequency: 0.195,
                pulse: 0.072
              }
            };

            /** Tham số shader-only + lắc: tách khỏi STATES để đọc được “nhịp” từng mode. */
            const ORB_VISUAL_BY_STATE = {
              idle: {
                pulseHz: 2.2,
                pointSizeMul: 0.96,
                ribbonDrift: 0.48,
                fragNoiseScale: 9.8,
                sway: 0.038
              },
              listening: {
                pulseHz: 4.35,
                pointSizeMul: 1.1,
                ribbonDrift: 1.2,
                fragNoiseScale: 15.0,
                sway: 0.08
              },
              thinking: {
                pulseHz: 6.0,
                pointSizeMul: 1.14,
                ribbonDrift: 1.65,
                fragNoiseScale: 19.5,
                sway: 0.098
              },
              speaking: {
                pulseHz: 2.75,
                pointSizeMul: 1.1,
                ribbonDrift: 0.9,
                fragNoiseScale: 12.2,
                sway: 0.056
              }
            };

            let currentState = "idle";
            let currentParams = Object.assign({}, STATES.idle, ORB_VISUAL_BY_STATE.idle);
            currentParams.color1 = STATES.idle.color1.clone();
            currentParams.color2 = STATES.idle.color2.clone();

            window.setJarvisEnergyState = (nextState, level) => {
              const s = typeof nextState === "string" ? nextState.trim().toLowerCase() : "";
              if (STATES[s]) currentState = s;
              externalLevel = clamp01(level);
            };

            const vertexShader = `
            uniform float uTime;
            uniform float uSpeed;
            uniform float uAmplitude;
            uniform float uFrequency;
            uniform float uPulse;
            uniform float uPulseHz;
            uniform float uPointSizeMul;
            uniform float uSpeechDrive;

            varying vec2 vUv;
            varying float vNoise;

            vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
            vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
            float snoise(vec3 v) {
              const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
              const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
              vec3 i = floor(v + dot(v, C.yyy));
              vec3 x0 = v - i + dot(i, C.xxx);
              vec3 g = step(x0.yzx, x0.xyz);
              vec3 l = 1.0 - g;
              vec3 i1 = min(g.xyz, l.zxy);
              vec3 i2 = max(g.xyz, l.zxy);
              vec3 x1 = x0 - i1 + C.xxx;
              vec3 x2 = x0 - i2 + C.yyy;
              vec3 x3 = x0 - D.yyy;
              i = mod289(i);
              vec4 p = permute(permute(permute(
                         i.z + vec4(0.0, i1.z, i2.z, 1.0))
                       + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                       + i.x + vec4(0.0, i1.x, i2.x, 1.0));
              float n_ = 0.142857142857;
              vec3 ns = n_ * D.wyz - D.xzx;
              vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
              vec4 x_ = floor(j * ns.z);
              vec4 y_ = floor(j - 7.0 * x_);
              vec4 x = x_ * ns.x + ns.yyyy;
              vec4 y = y_ * ns.x + ns.yyyy;
              vec4 h = 1.0 - abs(x) - abs(y);
              vec4 b0 = vec4(x.xy, y.xy);
              vec4 b1 = vec4(x.zw, y.zw);
              vec4 s0 = floor(b0) * 2.0 + 1.0;
              vec4 s1 = floor(b1) * 2.0 + 1.0;
              vec4 sh = -step(h, vec4(0.0));
              vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
              vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
              vec3 p0 = vec3(a0.xy, h.x);
              vec3 p1 = vec3(a0.zw, h.y);
              vec3 p2 = vec3(a1.xy, h.z);
              vec3 p3 = vec3(a1.zw, h.w);
              vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
              p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
              vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
              m = m * m;
              return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
            }

            void main() {
              vUv = uv;
              vNoise = snoise(position * uFrequency + uTime * uSpeed);
              float sd = clamp(uSpeechDrive, 0.0, 1.0);
              float talkPulse = sd * (
                0.14 * sin(uTime * 12.7 + position.x * 1.93) +
                0.09 * sin(uTime * 7.05 + position.y * 2.41 + 1.85) +
                0.055 * sin(uTime * 5.02 + dot(position.xyz, vec3(1.12, -0.67, 1.88)))
              );
              float pulseScale = 1.0 + sin(uTime * uPulseHz) * uPulse * 0.42 + talkPulse;
              float dispAmp = sd * sin(uTime * 9.3 + dot(position.xyz, vec3(0.72, -1.06, 1.97)));
              float displacement = vNoise * uAmplitude * 0.58 * (1.0 + 0.38 * sd * (0.55 + 0.45 * dispAmp));
              vec3 newPosition = (position * pulseScale) + (normal * displacement);
              vec4 mvPosition = modelViewMatrix * vec4(newPosition, 1.0);
              gl_PointSize = 1.65 * uPointSizeMul * (10.0 / -mvPosition.z);
              gl_Position = projectionMatrix * mvPosition;
            }
            `;

            const fragmentShader = `
            uniform vec3 uColor1;
            uniform vec3 uColor2;
            uniform float uTime;
            uniform float uRibbonDrift;
            uniform float uFragNoiseScale;
            uniform float uSpeechDriveFrag;
            varying float vNoise;

            void main() {
              vec2 xy = gl_PointCoord.xy - vec2(0.5);
              float ll = length(xy);
              if (ll > 0.5) discard;

              float mixRatio = smoothstep(-1.0, 1.0, vNoise);
              vec3 finalColor = mix(uColor1, uColor2, mixRatio);

              float ribbonDrift = uRibbonDrift * (1.0 + clamp(uSpeechDriveFrag, 0.0, 1.0) * 1.85);
              float ribbon = sin(vNoise * uFragNoiseScale - uTime * ribbonDrift);
              float alpha = smoothstep(-0.2, 0.2, ribbon);
              alpha *= (1.0 - ll * 2.0);

              gl_FragColor = vec4(finalColor, alpha * 0.9);
            }
            `;

            const PARTICLE_SHELL_R = 1.65;
            /** 1 = mọi đỉnh cầu vào hull (không sót tâm hạt do subsample). */
            const HULL_SAMPLE_STRIDE = 1;
            const HULL_MAX_TRIS = 2048;
            /** Slew RMS mỗi frame — cao = bám signal nhanh hơn, thấp = mượt hơn. */
            const EXTERNAL_LEVEL_SLEW = 0.05;
            /** Lắc quả cầu: biên rad — idle nhỏ nhất, thinking lớn nhất (không xoay trôi). */
            const ORB_SWAY_TIME_SCALE = 0.22;
            /** Ice Orb style: target/current easing chậm, mọi tham số đều trượt thay vì nhảy. */
            const PARTICLE_ORB_TRANSITION_LERP_MOTION = 0.02;
            const PARTICLE_ORB_TRANSITION_LERP_COLOR = 0.015;
            const SPEAKING_ENVELOPE_LERP = 0.22;
            const SPEECH_DRIVE_ATTACK = 0.28;
            const SPEECH_DRIVE_RELEASE = 0.06;

            function cross2(o, a, b) {
              return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
            }

            function convexHull2DMonotoneChain(points) {
              if (points.length < 3) return null;
              const sorted = points
                .slice()
                .sort((p, q) => (p[0] === q[0] ? p[1] - q[1] : p[0] - q[0]));
              const uniq = [];
              const eps = 1e-7;
              for (const p of sorted) {
                const last = uniq[uniq.length - 1];
                if (!last || Math.hypot(p[0] - last[0], p[1] - last[1]) > eps) uniq.push(p);
              }
              if (uniq.length < 3) return null;

              const lower = [];
              for (const p of uniq) {
                while (
                  lower.length >= 2 &&
                  cross2(lower[lower.length - 2], lower[lower.length - 1], p) <= 0
                ) {
                  lower.pop();
                }
                lower.push(p);
              }

              const upper = [];
              for (let i = uniq.length - 1; i >= 0; i--) {
                const p = uniq[i];
                while (
                  upper.length >= 2 &&
                  cross2(upper[upper.length - 2], upper[upper.length - 1], p) <= 0
                ) {
                  upper.pop();
                }
                upper.push(p);
              }

              upper.pop();
              lower.pop();
              return lower.concat(upper);
            }

            function init() {
              scene = new THREE.Scene();

              camera = new THREE.PerspectiveCamera(
                45,
                window.innerWidth / Math.max(window.innerHeight, 1),
                0.1,
                100
              );
              camera.position.z = 8;

              renderer = new THREE.WebGLRenderer({
                antialias: true,
                alpha: true,
                premultipliedAlpha: false
              });
              renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
              renderer.setSize(window.innerWidth, window.innerHeight);
              renderer.outputColorSpace = THREE.SRGBColorSpace;
              // Trong suốt ngoài vùng hạt; vùng đen = tam giác hóa bao lồi 2D (NDC) mỗi khung hình.
              renderer.setClearColor(0x000000, 0);

              orbGroup = new THREE.Group();

              const hullGeom = new THREE.BufferGeometry();
              const maxVerts = HULL_MAX_TRIS * 3;
              const hullPos = new Float32Array(maxVerts * 3);
              hullGeom.setAttribute("position", new THREE.BufferAttribute(hullPos, 3));
              hullGeom.setDrawRange(0, 0);
              hullBackdropMesh = new THREE.Mesh(
                hullGeom,
                new THREE.MeshBasicMaterial({
                  color: 0x000000,
                  side: THREE.DoubleSide,
                  depthWrite: true,
                  depthTest: true
                })
              );
              hullBackdropMesh.renderOrder = 0;
              hullBackdropMesh.frustumCulled = false;
              scene.add(hullBackdropMesh);

              container.appendChild(renderer.domElement);

              const geometry = new THREE.SphereGeometry(PARTICLE_SHELL_R, 160, 160);
              const material = new THREE.ShaderMaterial({
                vertexShader,
                fragmentShader,
                uniforms: {
                  uTime: { value: 0 },
                  uSpeed: { value: currentParams.speed },
                  uAmplitude: { value: currentParams.amplitude },
                  uFrequency: { value: currentParams.frequency },
                  uPulse: { value: currentParams.pulse },
                  uColor1: { value: currentParams.color1 },
                  uColor2: { value: currentParams.color2 },
                  uPulseHz: { value: ORB_VISUAL_BY_STATE.idle.pulseHz },
                  uPointSizeMul: { value: ORB_VISUAL_BY_STATE.idle.pointSizeMul },
                  uRibbonDrift: { value: ORB_VISUAL_BY_STATE.idle.ribbonDrift },
                  uFragNoiseScale: { value: ORB_VISUAL_BY_STATE.idle.fragNoiseScale },
                  uSpeechDrive: { value: 0 },
                  uSpeechDriveFrag: { value: 0 }
                },
                transparent: true,
                depthWrite: false,
                blending: THREE.NormalBlending
              });

              particles = new THREE.Points(geometry, material);
              particles.renderOrder = 2;

              orbGroup.add(particles);
              scene.add(orbGroup);
              window.addEventListener("resize", onResize);
            }

            const _vPos = new THREE.Vector3();
            const _vNrm = new THREE.Vector3();
            const _vDisp = new THREE.Vector3();
            const _vWorld = new THREE.Vector3();
            const _vUnproj = new THREE.Vector3();
            const _centerW = new THREE.Vector3();

            function updateScreenSpaceConvexHullFill() {
              if (!particles || !hullBackdropMesh) return;

              const posAttr = particles.geometry.attributes.position;
              const nrmAttr = particles.geometry.attributes.normal;
              if (!posAttr || !nrmAttr) return;

              const uTime = particles.material.uniforms.uTime.value;
              const uSpeed = particles.material.uniforms.uSpeed.value;
              const uAmp = particles.material.uniforms.uAmplitude.value;
              const uFreq = particles.material.uniforms.uFrequency.value;
              const uPulse = particles.material.uniforms.uPulse.value;
              const uPulseHz = particles.material.uniforms.uPulseHz.value;
              const uSpeechDrive = particles.material.uniforms.uSpeechDrive.value;
              const tTerm = uTime * uSpeed;
              const basePulseScale = 1.0 + Math.sin(uTime * uPulseHz) * uPulse * 0.42;

              orbGroup.updateMatrixWorld(true);

              _centerW.set(0, 0, 0).applyMatrix4(orbGroup.matrixWorld);
              _centerW.project(camera);
              const zHull = _centerW.z - 2e-4;

              const ndcPts = [];
              const count = posAttr.count;
              for (let i = 0; i < count; i += HULL_SAMPLE_STRIDE) {
                _vPos.fromBufferAttribute(posAttr, i);
                _vNrm.fromBufferAttribute(nrmAttr, i);

                const sn = shaderSnoise3(
                  _vPos.x * uFreq + tTerm,
                  _vPos.y * uFreq + tTerm,
                  _vPos.z * uFreq + tTerm
                );
                const sd = Math.min(Math.max(uSpeechDrive, 0), 1);
                const px = _vPos.x,
                  py = _vPos.y,
                  pz = _vPos.z;
                const talkPulse =
                  sd *
                  (0.14 * Math.sin(uTime * 12.7 + px * 1.93) +
                    0.09 * Math.sin(uTime * 7.05 + py * 2.41 + 1.85) +
                    0.055 * Math.sin(uTime * 5.02 + px * 1.12 + py * -0.67 + pz * 1.88));
                const pulseScale = basePulseScale + talkPulse;
                const dispAmp = sd * Math.sin(uTime * 9.3 + px * 0.72 + py * -1.06 + pz * 1.97);
                const dispMul = 1.0 + 0.38 * sd * (0.55 + 0.45 * dispAmp);
                _vDisp.copy(_vPos).multiplyScalar(pulseScale);
                _vDisp.addScaledVector(_vNrm, sn * uAmp * 0.58 * dispMul);

                _vWorld.copy(_vDisp).applyMatrix4(orbGroup.matrixWorld);
                _vWorld.project(camera);
                ndcPts.push([_vWorld.x, _vWorld.y]);
              }

              const hull = convexHull2DMonotoneChain(ndcPts);
              const geom = hullBackdropMesh.geometry;
              const buf = geom.attributes.position.array;

              if (!hull || hull.length < 3) {
                geom.setDrawRange(0, 0);
                hullBackdropMesh.visible = false;
                return;
              }

              hullBackdropMesh.visible = true;
              const m = hull.length;
              const triCount = m - 2;
              if (triCount > HULL_MAX_TRIS) {
                geom.setDrawRange(0, 0);
                hullBackdropMesh.visible = false;
                return;
              }

              let o = 0;
              const p0x = hull[0][0];
              const p0y = hull[0][1];
              _vUnproj.set(p0x, p0y, zHull);
              _vUnproj.unproject(camera);

              const ax = _vUnproj.x;
              const ay = _vUnproj.y;
              const az = _vUnproj.z;

              for (let k = 1; k < m - 1; k++) {
                _vUnproj.set(hull[k][0], hull[k][1], zHull);
                _vUnproj.unproject(camera);
                const bx = _vUnproj.x;
                const by = _vUnproj.y;
                const bz = _vUnproj.z;

                _vUnproj.set(hull[k + 1][0], hull[k + 1][1], zHull);
                _vUnproj.unproject(camera);
                const cx = _vUnproj.x;
                const cy = _vUnproj.y;
                const cz = _vUnproj.z;

                buf[o++] = ax;
                buf[o++] = ay;
                buf[o++] = az;
                buf[o++] = bx;
                buf[o++] = by;
                buf[o++] = bz;
                buf[o++] = cx;
                buf[o++] = cy;
                buf[o++] = cz;
              }

              geom.attributes.position.needsUpdate = true;
              geom.setDrawRange(0, triCount * 3);
            }

            function onResize() {
              const h = Math.max(window.innerHeight, 1);
              camera.aspect = window.innerWidth / h;
              camera.updateProjectionMatrix();
              renderer.setSize(window.innerWidth, h);
            }

            function animate() {
              requestAnimationFrame(animate);
              const elapsedTime = clock.getElapsedTime();

              smoothedExternalLevel += (externalLevel - smoothedExternalLevel) * EXTERNAL_LEVEL_SLEW;

              const speechTarget = currentState === "speaking" ? 1 : 0;
              const speechSlew =
                speechTarget > speechDrive ? SPEECH_DRIVE_ATTACK : SPEECH_DRIVE_RELEASE;
              speechDrive += (speechTarget - speechDrive) * speechSlew;

              const speakingTargetEnvelope =
                currentState === "speaking"
                  ? clamp01(
                      0.52 +
                        0.28 * Math.sin(elapsedTime * 4.4) +
                        0.2 * Math.sin(elapsedTime * 7.1 + 1.35)
                    )
                  : 0;
              speakingEnvelope +=
                (speakingTargetEnvelope - speakingEnvelope) * SPEAKING_ENVELOPE_LERP;

              let targetDef = STATES[currentState];
              const lvl = smoothedExternalLevel;
              if (lvl > 0.02) {
                if (currentState === "listening") {
                  const ampBoost = lvl * 0.018;
                  const spdBoost = lvl * 0.018;
                  const pulBoost = lvl * 0.0025;
                  targetDef = {
                    ...targetDef,
                    amplitude: targetDef.amplitude + ampBoost,
                    speed: targetDef.speed + spdBoost,
                    pulse: Math.min(targetDef.pulse + pulBoost, 0.028)
                  };
                } else if (currentState === "speaking") {
                  const ampBoost = lvl * 0.012;
                  const spdBoost = lvl * 0.008;
                  const pulBoost = lvl * 0.018;
                  targetDef = {
                    ...targetDef,
                    amplitude: targetDef.amplitude + ampBoost,
                    speed: targetDef.speed + spdBoost,
                    pulse: Math.min(targetDef.pulse + pulBoost, 0.095)
                  };
                }
              }

              currentParams.color1.lerp(targetDef.color1, PARTICLE_ORB_TRANSITION_LERP_COLOR);
              currentParams.color2.lerp(targetDef.color2, PARTICLE_ORB_TRANSITION_LERP_COLOR);
              currentParams.speed = THREE.MathUtils.lerp(
                currentParams.speed,
                targetDef.speed,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.amplitude = THREE.MathUtils.lerp(
                currentParams.amplitude,
                targetDef.amplitude,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.frequency = THREE.MathUtils.lerp(
                currentParams.frequency,
                targetDef.frequency,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.pulse = THREE.MathUtils.lerp(
                currentParams.pulse,
                targetDef.pulse,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );

              const ov = ORB_VISUAL_BY_STATE[currentState] || ORB_VISUAL_BY_STATE.idle;
              currentParams.pulseHz = THREE.MathUtils.lerp(
                currentParams.pulseHz,
                ov.pulseHz,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.pointSizeMul = THREE.MathUtils.lerp(
                currentParams.pointSizeMul,
                ov.pointSizeMul,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.ribbonDrift = THREE.MathUtils.lerp(
                currentParams.ribbonDrift,
                ov.ribbonDrift,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.fragNoiseScale = THREE.MathUtils.lerp(
                currentParams.fragNoiseScale,
                ov.fragNoiseScale,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );
              currentParams.sway = THREE.MathUtils.lerp(
                currentParams.sway,
                ov.sway,
                PARTICLE_ORB_TRANSITION_LERP_MOTION
              );

              if (!particles?.material.uniforms) return;

              const speechMotion = currentState === "speaking" ? speakingEnvelope : 0;
              const renderAmplitude = currentParams.amplitude + speechMotion * 0.024;
              const renderPulse = currentParams.pulse + speechMotion * 0.095;
              const renderPointSizeMul = currentParams.pointSizeMul + speechMotion * 0.098;

              particles.material.uniforms.uTime.value = elapsedTime;
              particles.material.uniforms.uSpeed.value = currentParams.speed;
              particles.material.uniforms.uAmplitude.value = renderAmplitude;
              particles.material.uniforms.uFrequency.value = currentParams.frequency;
              particles.material.uniforms.uPulse.value = renderPulse;
              particles.material.uniforms.uColor1.value = currentParams.color1;
              particles.material.uniforms.uColor2.value = currentParams.color2;

              particles.material.uniforms.uPulseHz.value = currentParams.pulseHz;
              particles.material.uniforms.uPointSizeMul.value = renderPointSizeMul;
              particles.material.uniforms.uRibbonDrift.value = currentParams.ribbonDrift;
              particles.material.uniforms.uFragNoiseScale.value = currentParams.fragNoiseScale;
              particles.material.uniforms.uSpeechDrive.value = speechDrive;
              particles.material.uniforms.uSpeechDriveFrag.value = speechDrive;

              const ts = elapsedTime * ORB_SWAY_TIME_SCALE;
              const sway = currentParams.sway;
              orbGroup.rotation.y = Math.sin(ts) * sway + Math.sin(ts * 1.07 + 0.5) * sway * 0.38;
              orbGroup.rotation.x = Math.sin(ts * 0.55 + 2.1) * sway * 0.5;

              updateScreenSpaceConvexHullFill();

              renderer.render(scene, camera);
            }

            init();
            animate();
          </script>
        </head>
        <body>
          <div id="canvas-container"></div>
        </body>
        </html>
        """
    }
}
