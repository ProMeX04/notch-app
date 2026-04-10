# Phân tích Hiệu năng Ứng dụng Notch

> [!IMPORTANT]
> Tài liệu này liệt kê **tất cả** các vấn đề hiệu năng đã phát hiện, phân loại theo mức độ nghiêm trọng, kèm giải pháp cụ thể và đoạn code minh họa.

---

## Tổng quan

Sau khi rà soát toàn bộ mã nguồn, tôi đã phát hiện **14 vấn đề hiệu năng** trải rộng trên 4 module chính:

| Module | Nghiêm trọng | Trung bình | Nhẹ |
|---|---|---|---|
| **GeminiLive** (ViewModel + Session + Audio) | 3 | 4 | 1 |
| **UI / SwiftUI Views** | 1 | 1 | — |
| **Media / Now Playing** | — | 1 | 1 |
| **Khác** (Tools, Extensions) | — | 1 | 1 |

---

## 🔴 Nghiêm trọng (Ảnh hưởng trực tiếp tới trải nghiệm)

### 1. Screen Capture Timer chạy trên Main Thread

**File:** [GeminiLiveViewModel.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveViewModel.swift#L1177-L1183)

```swift
// HIỆN TẠI — timer callback trên main thread, rồi lại await capture trên main
screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
    Task { @MainActor in
        self.updateScreenShareHighlight()
        guard let jpeg = await GeminiLiveViewModel.captureAndEncodeScreen(...) else { return }
        captureSession.sendScreenFrame(jpeg)
    }
}
```

**Vấn đề:** `Timer.scheduledTimer` fire trên **main RunLoop**. Callback tạo một `Task` trên `@MainActor`, gọi `captureAndEncodeScreen` — hàm này:
- Gọi `CGWindowListCreateImage()` (tốn ~20-50ms)
- Tạo `CGContext`, resize ảnh, encode JPEG (~10-30ms)

Dù `captureAndEncodeScreen` là `nonisolated`, nó vẫn được `await` trên MainActor => main thread phải chờ kết quả. Mỗi 1.5s, main thread bị block **30-80ms**, gây micro-stutter rõ rệt khi chia sẻ màn hình.

**Giải pháp:**
```swift
// ĐỀ XUẤT — chạy capture hoàn toàn off-main
private func beginScreenCapture(statusMessage: String) {
    pauseScreenCapture()
    isScreenSharingEnabled = true
    statusText = statusMessage
    updateScreenShareHighlight()
    
    let captureRegion = screenShareRegion
    let captureFilter = screenShareFilter
    
    screenCaptureTask = Task.detached(priority: .userInitiated) { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { break }
            
            guard let jpeg = await GeminiLiveViewModel.captureAndEncodeScreen(
                region: captureRegion, contentFilter: captureFilter
            ) else { continue }
            
            await MainActor.run { [weak self] in
                self?.updateScreenShareHighlight()
            }
            self?.session.sendScreenFrame(jpeg)
        }
    }
}
```

---

### 2. `runProcess` dùng RunLoop polling — block calling thread  

**File:** [GeminiLiveSession+Tools.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveSession+Tools.swift#L400-L410)

```swift
// Busy-wait loop chạy trên calling thread
if let timeout {
    let deadline = Date().addingTimeInterval(timeout)
    while task.isRunning && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))  // ⚠️ poll mỗi 50ms
    }
    if task.isRunning {
        didTimeOut = true
        task.terminate()
    }
}

task.waitUntilExit()  // Block nữa
```

**Vấn đề:** Khi Gemini gọi tool `exec`, hàm này **block thread hiện tại** (thường là thread xử lý tool dispatch) trong tối đa **30 giây** bằng RunLoop polling. Nếu tool dispatch chạy trên main thread hoặc queue dùng chung, toàn bộ app sẽ freeze.

**Giải pháp:**
```swift
private func runProcess(
    executablePath: String,
    arguments: [String],
    currentDirectoryURL: URL? = nil,
    timeout: TimeInterval? = nil
) async -> ProcessResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executablePath)
    task.arguments = arguments
    task.currentDirectoryURL = currentDirectoryURL

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    task.standardOutput = stdoutPipe
    task.standardError = stderrPipe

    do {
        try task.run()
    } catch {
        return ProcessResult(terminationStatus: nil, stdoutText: "", stderrText: "",
                            runError: error.localizedDescription, timedOut: false)
    }

    // Non-blocking wait with timeout
    let didTimeOut = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            task.waitUntilExit()
            return false
        }
        if let timeout {
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                if task.isRunning { task.terminate() }
                return true
            }
        }
        return await group.next() ?? false
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
        terminationStatus: task.terminationStatus,
        stdoutText: String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        stderrText: String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        runError: nil,
        timedOut: didTimeOut
    )
}
```

---

### 3. Audio Buffer Clone trên mỗi capture callback — allocation overhead

**File:** [GeminiLiveWebRTCAudioIO.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveWebRTCAudioIO.swift#L293-L327)

```swift
// Mỗi audio callback (~10ms) phải clone toàn bộ buffer
private func clone(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let clone = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
        return nil
    }
    clone.frameLength = buffer.frameLength
    // ... memcpy cho mỗi channel
}
```

**Vấn đề:** Audio capture callback fire **~100 lần/giây** (10ms interval, bufferSize 512 @ 48kHz). Mỗi lần tạo một `AVAudioPCMBuffer` mới + `memcpy`. Điều này tạo **~100 heap allocations/sec**, gây áp lực lên ARC và có thể trigger garbage collection pauses.

**Giải pháp: Ring buffer pool**
```swift
private final class PCMBufferPool {
    private let format: AVAudioFormat
    private let capacity: AVAudioFrameCount
    private var pool: [AVAudioPCMBuffer] = []
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    init(format: AVAudioFormat, capacity: AVAudioFrameCount, poolSize: Int = 4) {
        self.format = format
        self.capacity = capacity
        lock.initialize(to: os_unfair_lock())
        for _ in 0..<poolSize {
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) {
                pool.append(buffer)
            }
        }
    }
    
    func acquire() -> AVAudioPCMBuffer? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return pool.isEmpty ? AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) : pool.removeLast()
    }
    
    func release(_ buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if pool.count < 8 { pool.append(buffer) }
    }
}
```

---

## 🟠 Trung bình (Tiêu tốn tài nguyên không cần thiết)

### 4. `ProgressiveRevealText` render lại toàn bộ text mỗi frame

**File:** [NotchGeminiTalkViews.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Music/NotchGeminiTalkViews.swift#L1462-L1475)

```swift
// Trong GeminiTranscriptCard
ScrollView(.vertical, showsIndicators: false) {
    Group {
        if revealsProgressively {
            ProgressiveRevealText(text: text, animateOnAppear: false) // ⚠️
        } else {
            Text(text)
        }
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(.white.opacity(0.92))
    .lineLimit(showsFullText ? nil : 3)
    ...
}
```

**Vấn đề:** Khi `text` (transcript) dài, `ProgressiveRevealText` tạo animation reveal từng ký tự. SwiftUI phải re-layout toàn bộ `Text` view mỗi khi có character mới. Với transcript dài 5000+ ký tự, đây là **O(n²)** rendering — mỗi update re-measure toàn bộ string.

**Giải pháp:** Chỉ render phần đuôi của transcript (cuối cùng ~500 ký tự) và dùng `equatable()` modifier:
```swift
// Chỉ animate phần mới nhất
let displayText = text.count > 500 ? String(text.suffix(500)) : text

if revealsProgressively {
    ProgressiveRevealText(text: displayText, animateOnAppear: false)
        .equatable()
} else {
    Text(displayText)
}
```

---

### 5. `encodeJPEG` tạo CGContext + NSBitmapImageRep mỗi 1.5s

**File:** [GeminiLiveViewModel.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveViewModel.swift#L1259-L1283)

```swift
private nonisolated static func encodeJPEG(from fullImage: CGImage) -> Data? {
    // Tạo mới CGContext MỖI LẦN
    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        ...
    ) else { return nil }

    context.draw(fullImage, in: ...)
    guard let scaled = context.makeImage() else { return nil }
    
    // Tạo mới NSBitmapImageRep MỖI LẦN
    let bitmapRep = NSBitmapImageRep(cgImage: scaled)
    return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
}
```

**Vấn đề:** Mỗi 1.5s phải allocate/deallocate một `CGContext` buffer (~4MB cho 1280px) và `NSBitmapImageRep`. Trong phiên dài (30+ phút), accumulated allocation pressure có thể trigger memory warnings.

**Giải pháp:** Cache CGContext giữa các lần capture:
```swift
// Reuse CIContext cho JPEG encoding — tối ưu hơn rất nhiều
private static let jpegContext = CIContext(options: [.useSoftwareRenderer: false])

private nonisolated static func encodeJPEG(from fullImage: CGImage) -> Data? {
    let maxWidth: CGFloat = 1280
    let scale = min(1.0, maxWidth / CGFloat(fullImage.width))
    let targetWidth = Int(CGFloat(fullImage.width) * scale)
    let targetHeight = Int(CGFloat(fullImage.height) * scale)
    
    let ciImage = CIImage(cgImage: fullImage)
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return jpegContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6])
}
```

---

### 6. `averageColor` compute trên mỗi artwork change — không cần thiết nếu ảnh giống

**File:** [VisualExtensions.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Support/VisualExtensions.swift#L7-L87)

```swift
func averageColor(completion: @Sendable @escaping (NSColor?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        // Tính toán pixel-by-pixel trên ảnh 40x40 => ~1600 iterations
        ...
    }
}
```

**Vấn đề:** Mặc dù `MusicProbeViewModel.updateVisualState` đã có `VisualSignature` check, nhưng mỗi khi track đổi, hàm này vẫn dispatch sang background thread + dispatch lại main thread. Trong trường hợp skip nhanh nhiều bài, nhiều background tasks chồng chéo.

**Giải pháp:** Đã có `artworkComputationToken` (tốt!), nhưng nên thêm cancellation:
```swift
private var artworkTask: Task<Void, Never>?

private func updateAccentColor() {
    artworkTask?.cancel()
    let image = albumArt
    
    artworkTask = Task.detached(priority: .utility) { [weak self] in
        guard !Task.isCancelled else { return }
        let color = image.computeAverageColor()  // sync version
        guard !Task.isCancelled else { return }
        
        await MainActor.run {
            self?.accentColor = color ?? .white
        }
    }
}
```

---

### 7. WebSocket message parsing dùng `JSONSerialization` — tạo nhiều temp objects

**File:** [GeminiLiveSession.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveSession.swift) (message handling)

**Vấn đề:** Mỗi WebSocket message (đặc biệt audio chunks — rất thường xuyên) đều qua `JSONSerialization.jsonObject()` tạo temporary `NSDictionary`/`NSArray`. Với audio stream 24kHz mono, server gửi ~3-5 messages/sec, mỗi message chứa base64 audio data.

**Giải pháp:** Không cần thay đổi parser, nhưng nên dùng `autoreleasepool` cho hot path:
```swift
func handleWebSocketMessage(_ data: Data) {
    autoreleasepool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        processMessage(json)
    }
}
```

---

### 8. `toolHTTPURLSession` không cấu hình connection pooling

**File:** [GeminiLiveSession+Tools.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveSession+Tools.swift#L117)

```swift
toolHTTPURLSession.dataTask(with: request) { [weak self] data, _, error in
    // callback trả về trên background thread — không có @MainActor dispatch
    self.notifyFunctionExecuted(name: name, args: args, result: result)
    self.sendFunctionResponse(id: id, name: name, result: result) 
}
```

**Vấn đề:** `notifyFunctionExecuted` gọi callback `onFunctionExecuted` — callback này trong `GeminiLiveViewModel` sẽ cập nhật `@Published` properties. Nếu callback fire trên background thread mà cập nhật `@Published`, SwiftUI sẽ crash hoặc gây race condition.

**Giải pháp:** Verify tất cả callbacks đều dispatch sang đúng thread. Nếu `notifyFunctionExecuted` triggers UI update, nó phải chạy trên main.

---

### 9. `NowPlayingController.shutdown()` gọi `Process.waitUntilExit()` — có thể block main

**File:** [NowPlayingController.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Music/NowPlayingController.swift#L87-L114)

```swift
func shutdown() {
    // ...
    if let process, process.isRunning {
        process.terminate()
        process.waitUntilExit()  // ⚠️ Block main thread

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
```

**Vấn đề:** `shutdown()` có `@MainActor` annotation (inherited from class). `waitUntilExit()` là blocking call — nếu subprocess không thoát ngay sau `terminate()`, main thread bị block.

**Giải pháp:**
```swift
func shutdown() {
    // ...
    if let process, process.isRunning {
        process.terminate()
        // Set timeout rồi SIGKILL thay vì block
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
    process = nil
}
```

---

## 🟡 Nhẹ (Tối ưu hóa thêm)

### 10. `GeminiAgentAvatarArtwork` load `NSImage(contentsOf:)` synchronously

**File:** [NotchGeminiTalkViews.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Music/NotchGeminiTalkViews.swift#L922-L937)

```swift
if let imageURL, let image = NSImage(contentsOf: imageURL) {  // ⚠️ Sync disk I/O
    Image(nsImage: image)
        .resizable()
        .scaledToFill()
        ...
}
```

**Vấn đề:** Mỗi lần SwiftUI re-render avatar (hover, state change), nó đọc file từ disk synchronously. Nếu có nhiều agents hoặc file lớn, gây micro-stutter.

**Giải pháp:** Cache image bằng `NSCache` hoặc dùng `AsyncImage` pattern.

---

### 11. `MusicVisualizer` `Timer.scheduledTimer` interval 0.3s — hơi wasteful khi paused

**File:** [MusicVisualizer.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Music/MusicVisualizer.swift#L56-L61)

```swift
animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.updateBars()  // 4 CABasicAnimation mỗi 300ms
    }
}
```

**Vấn đề nhỏ:** Timer vẫn fire khi notch collapsed (view vẫn trong hierarchy nhưng không visible). Đã có `viewDidMoveToWindow` guard nhưng `window` vẫn present khi notch collapsed — chỉ invisible.

---

### 12. `ensureMinimumBrightness` allocates `NSColor` → sRGB conversion mỗi lần gọi

**File:** [VisualExtensions.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Support/VisualExtensions.swift#L90-L116)

```swift
func ensureMinimumBrightness(factor: CGFloat) -> Color {
    guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return self }
    // ...
}
```

**Vấn đề nhỏ:** `NSColor(self)` tạo bridging object, `usingColorSpace` allocate thêm. Hàm này được gọi trong `body` của nhiều views → mỗi SwiftUI render cycle tạo temporary objects. Trong phiên Pomodoro với timer update mỗi giây, đây là ~2-3 allocation/sec.

---

### 13. `PomodoroDigitColumn` renders 10 `Text` views cho mỗi digit

**File:** [NotchFocusPanels.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/Music/NotchFocusPanels.swift#L546-L558)

```swift
VStack(spacing: 0) {
    ForEach(0..<10, id: \.self) { value in
        Text("\(value)")
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .frame(width: digitWidth, height: digitHeight)
    }
}
.offset(y: -CGFloat(digit) * digitHeight)
.frame(width: digitWidth, height: digitHeight, alignment: .top)
.clipped()
```

**Vấn đề nhỏ:** Mỗi digit column render **10 Text views**, nhưng chỉ 1 visible (clipped). Timer update mỗi giây → 4 columns × 10 texts = **40 Text views re-rendered/sec**. Không nghiêm trọng nhưng inefficient.

---

### 14. `@Published` properties chain reactions trong `GeminiLiveViewModel`

**File:** [GeminiLiveViewModel.swift](file:///Users/promex04/Documents/NO/notch-app/Sources/Notch/GeminiLive/GeminiLiveViewModel.swift)

**Vấn đề:** ViewModel chứa **rất nhiều** `@Published` properties (transcript, connectionState, statusText, isScreenSharing, etc.). Mỗi thay đổi 1 property → Combine fire `objectWillChange` → SwiftUI re-evaluate **tất cả** views đang observe ViewModel này.

Ví dụ: khi `userTranscript` update (nhiều lần/giây khi nói), toàn bộ settings panel, tool picker, agent selector... đều bị re-evaluate dù chúng không hiển thị transcript.

**Giải pháp lâu dài:** Tách ViewModel thành các sub-ViewModels nhỏ hơn:
```
GeminiLiveViewModel (coordinator)
├── TranscriptViewModel (@Published userText, modelText)
├── ConnectionViewModel (@Published state, status, error)
├── ScreenShareModel (@Published isEnabled, mode)
└── ToolsViewModel (@Published lastAction, pendingApprovals)
```

---

## Thứ tự ưu tiên sửa

| # | Vấn đề | Impact | Effort | ROI |
|---|---|---|---|---|
| 1 | Screen capture trên main thread | 🔴 High | 🟢 Low | ⭐⭐⭐ |
| 2 | `runProcess` blocking | 🔴 High | 🟡 Medium | ⭐⭐⭐ |
| 3 | Audio buffer clone overhead | 🔴 High | 🟡 Medium | ⭐⭐ |
| 9 | `waitUntilExit()` on main | 🟠 Med | 🟢 Low | ⭐⭐⭐ |
| 5 | JPEG encode allocation | 🟠 Med | 🟢 Low | ⭐⭐ |
| 14 | `@Published` chain reactions | 🟠 Med | 🔴 High | ⭐ |
| 4 | Progressive text O(n²) | 🟠 Med | 🟢 Low | ⭐⭐ |

> [!TIP]
> **Bước tiếp theo:** Nếu bạn muốn, tôi có thể bắt đầu sửa từ vấn đề #1 (screen capture) và #9 (`waitUntilExit`) — đây là 2 thay đổi có ROI cao nhất vì effort thấp mà impact lớn.
