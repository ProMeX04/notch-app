# Focus Redesign Without Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the focus panel into a notch-native timer-first layout and remove fullscreen mode from the focus feature end-to-end.

**Architecture:** Keep pomodoro behavior in `NotchFocusCore`, but strip out fullscreen presentation state from the core view model. Refactor the focus panel into a centered hero layout with a state-driven command dock, then remove the separate fullscreen window controller and update docs to match the new single-surface model.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, Swift Package Manager executable targets (`Notch`, `NotchFocusTests`)

---

## File Structure

### Modify

- `Package.swift`
  - Remove the fullscreen controller source from the executable target implicitly by deleting the file from `Sources/Notch/Focus`.
- `Sources/NotchFocusCore/PomodoroViewModel.swift`
  - Remove `PomodoroFocusMode`, `focusMode`, `isFullscreenActive`, and all fullscreen evaluation/exit logic.
  - Preserve timer/session behavior and persistence for all remaining fields.
- `Sources/Notch/Music/NotchFocusPanels.swift`
  - Replace the current left-rail/right-rail layout with a centered timer-first layout.
  - Remove the focus mode menu and add a state-driven command dock.
- `Sources/Notch/Window/NotchWindowController.swift`
  - Remove fullscreen-overlay lifecycle wiring and visibility syncing.
- `Sources/Notch/docs/focus-mechanism.html`
  - Remove `Off / Zen / Strict` language and fullscreen-specific explanations.
- `Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift`
  - Add regression tests for core pomodoro behaviors that must remain stable after fullscreen removal.
- `Tests/NotchFocusTests/main.swift`
  - Register any new regression tests added in `PomodoroViewModelP0Tests.swift`.

### Create

- `Sources/Notch/Focus/PomodoroPanelComponents.swift`
  - Extract small focus-panel subviews so `PomodoroPanelView` stays readable:
    - `FocusHeaderRow`
    - `FocusHeroTimer`
    - `FocusTaskLabel`
    - `FocusCommandDock`

### Delete

- `Sources/Notch/Focus/PomodoroFullscreenWindowController.swift`
  - Remove the fullscreen overlay implementation entirely.

---

### Task 1: Lock Core Pomodoro Behavior Before Removing Fullscreen State

**Files:**
- Modify: `Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift`
- Modify: `Tests/NotchFocusTests/main.swift`
- Test: `Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift`

- [ ] **Step 1: Write the failing regression tests**

Add two tests to `Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift` after `manualPauseThenSkipDoesNotAutoResume()`:

```swift
    static func pausePreservesRemainingSecondsWithoutFullscreenSideEffects() throws {
        let clock = TestPomodoroClock(now: Date(timeIntervalSince1970: 9_000))
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "pause-preserves-remaining"),
            clock: clock,
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 10, breakSeconds: 3)
        vm.start()
        clock.now = clock.now.addingTimeInterval(4)

        vm.pause()

        try expect(!vm.isRunning)
        try expect(vm.hasActiveSession)
        try expectEqual(vm.remainingSeconds, 6)
        try expectEqual(vm.phase, .focus)
    }

    static func resetReturnsToIdleFocusBaseline() throws {
        let clock = TestPomodoroClock(now: Date(timeIntervalSince1970: 10_000))
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "reset-focus-baseline"),
            clock: clock,
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 12, breakSeconds: 4)
        vm.start()
        vm.skipPhase()
        vm.reset()

        try expect(!vm.isRunning)
        try expect(!vm.hasActiveSession)
        try expectEqual(vm.phase, .focus)
        try expectEqual(vm.remainingSeconds, 12)
        try expectEqual(vm.completedFocusSessions, 0)
    }
```

Register both in `Tests/NotchFocusTests/main.swift`:

```swift
        TestCase(
            name: "focus/pause preserves remaining seconds without fullscreen side effects",
            run: PomodoroViewModelTests.pausePreservesRemainingSecondsWithoutFullscreenSideEffects
        ),
        TestCase(
            name: "focus/reset returns to idle focus baseline",
            run: PomodoroViewModelTests.resetReturnsToIdleFocusBaseline
        ),
```

- [ ] **Step 2: Run the tests to verify the new coverage passes before refactor**

Run:

```bash
swift run NotchFocusTests
```

Expected:

```text
PASS  focus/pause preserves remaining seconds without fullscreen side effects
PASS  focus/reset returns to idle focus baseline
========== NotchFocusTests summary ==========
11/11 passed, 0 failed
```

- [ ] **Step 3: Remove fullscreen state from the core view model**

In `Sources/NotchFocusCore/PomodoroViewModel.swift`, delete the fullscreen enum and published properties near lines 56-60 and 145-146:

```swift
package enum PomodoroFocusMode: String, CaseIterable, Codable {
    case off = "Off"
    case zen = "Zen"
    case strict = "Strict"
}
```

and:

```swift
    @Published package private(set) var focusMode: PomodoroFocusMode { didSet { persistSettings() } }
    @Published package private(set) var isFullscreenActive = false
```

Replace the initializer portion around lines 223-224 with nothing:

```swift
        let rawFocusMode = userDefaults.string(forKey: Self.focusModeKey) ?? ""
        self.focusMode = PomodoroFocusMode(rawValue: rawFocusMode) ?? .off
```

Remove fullscreen-only branches from lifecycle methods. The resulting methods should look like this:

```swift
    package func start() {
        start(force: false)
    }

    private func start(force: Bool) {
        guard force || !isRunning else { return }
        hasActiveSession = true
        isRunning = true
        wasManuallyPaused = false
        phaseEndDate = nowProvider().addingTimeInterval(TimeInterval(remainingSeconds))
        startPhaseCompletionTask()
        persistRuntimeState()
    }

    package func reset() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus)
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        persistRuntimeState()
        refreshPhaseReminder()
    }

    package func shutdown() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        flushPendingPersistence()
        persistSettingsImmediately()
        persistRuntimeStateImmediately()
        persistTasksImmediately()
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        scheduledPhaseTaskID = UUID()
        sleepWakeCancellables.removeAll()
        providerCancellables.removeAll()
    }
```

Delete these methods entirely by name:

```swift
    package func setFocusMode(_ mode: PomodoroFocusMode)
    private func evaluateFullscreenState()
    package func exitFullscreen()
```

Delete the stale settings persistence line and key:

```swift
        userDefaults.set(focusMode.rawValue, forKey: Self.focusModeKey)
```

```swift
    private static let focusModeKey = "NotchPomodoroFocusMode"
```

- [ ] **Step 4: Run the regression suite again**

Run:

```bash
swift run NotchFocusTests
```

Expected:

```text
PASS  focus/pause preserves remaining seconds without fullscreen side effects
PASS  focus/reset returns to idle focus baseline
========== NotchFocusTests summary ==========
11/11 passed, 0 failed
```

- [ ] **Step 5: Commit the core cleanup**

Run:

```bash
git add Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift Tests/NotchFocusTests/main.swift Sources/NotchFocusCore/PomodoroViewModel.swift
git commit -m "refactor: remove pomodoro fullscreen state"
```

---

### Task 2: Remove Fullscreen Window Wiring From the App Shell

**Files:**
- Modify: `Sources/Notch/Window/NotchWindowController.swift`
- Delete: `Sources/Notch/Focus/PomodoroFullscreenWindowController.swift`
- Test: `Sources/Notch/Window/NotchWindowController.swift`

- [ ] **Step 1: Write the failing build expectation**

Capture the current references that must disappear from `Sources/Notch/Window/NotchWindowController.swift`:

```swift
    private let pomodoroFullscreenOverlay = PomodoroFullscreenWindowController()
```

```swift
        pomodoroViewModel.$isFullscreenActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFullscreenActive in
                self?.syncVisibilityForPomodoroFullscreen(isFullscreenActive)
            }
            .store(in: &cancellables)
```

```swift
    private func syncVisibilityForPomodoroFullscreen(_ isFullscreenActive: Bool)
    private func applyWindowVisibility(_ visible: Bool)
```

This step is “red” because deleting `PomodoroFullscreenWindowController.swift` before removing these references should break `swift build --product Notch`.

- [ ] **Step 2: Run the build red check**

Temporarily move the fullscreen controller out of the target to prove the references are real:

```bash
mv Sources/Notch/Focus/PomodoroFullscreenWindowController.swift /tmp/PomodoroFullscreenWindowController.swift
swift build --product Notch
mv /tmp/PomodoroFullscreenWindowController.swift Sources/Notch/Focus/PomodoroFullscreenWindowController.swift
```

Expected:

```text
error: cannot find 'PomodoroFullscreenWindowController' in scope
error: value of type 'PomodoroViewModel' has no member '$isFullscreenActive'
```

- [ ] **Step 3: Remove the fullscreen controller and shell wiring**

Update `Sources/Notch/Window/NotchWindowController.swift` so the property block becomes:

```swift
    private let transcriptOverlay = TranscriptOverlayWindowController()
    private let liveChatInputPanel = GeminiLiveChatInputWindowController()
    private let geminiExecApprovalPanel = GeminiExecApprovalPanelController()
```

Delete the fullscreen Combine subscription around lines 92-98 and remove these lifecycle calls:

```swift
        pomodoroFullscreenOverlay.setPreferredScreen(initialScreen)
        pomodoroFullscreenOverlay.observe(pomodoro: pomodoroViewModel, stats: learningStatsStore)
```

```swift
        pomodoroFullscreenOverlay.stopObserving()
```

Delete the helper methods:

```swift
    private func syncVisibilityForPomodoroFullscreen(_ isFullscreenActive: Bool)
    private func applyWindowVisibility(_ visible: Bool)
```

Then delete the file:

```bash
rm Sources/Notch/Focus/PomodoroFullscreenWindowController.swift
```

- [ ] **Step 4: Build the app to verify the shell compiles without fullscreen support**

Run:

```bash
swift build --product Notch
```

Expected:

```text
Build of product 'Notch' complete!
```

- [ ] **Step 5: Commit the shell cleanup**

Run:

```bash
git add Sources/Notch/Window/NotchWindowController.swift Sources/Notch/Focus/PomodoroFullscreenWindowController.swift
git commit -m "refactor: remove focus fullscreen window"
```

---

### Task 3: Rebuild the Focus Panel Around a Timer-First Command Dock

**Files:**
- Create: `Sources/Notch/Focus/PomodoroPanelComponents.swift`
- Modify: `Sources/Notch/Music/NotchFocusPanels.swift`
- Test: `Sources/Notch/Music/NotchFocusPanels.swift`

- [ ] **Step 1: Write the failing view-level build target**

The current layout in `Sources/Notch/Music/NotchFocusPanels.swift:75-199` still uses three zones and a focus-mode menu:

```swift
                ZStack {
                    // Center area
                    VStack(spacing: 8) {
                        Text(Localization.get(displayedPhase.rawValue, lang: appLanguage))
                        if pomodoro.hasActiveSession {
                            HStack(spacing: 8) {
                                PomodoroSessionDotsView(
                                    current: pomodoro.completedSessionsInCycle,
                                    total: pomodoro.sessionsBeforeLongBreak,
                                    isFocus: pomodoro.phase == .focus,
                                    tint: displayedTint
                                )

                                Text("\(Localization.get("Round", lang: appLanguage)) \(pomodoro.currentFocusSessionIndex)/\(pomodoro.sessionsBeforeLongBreak)")
                            }
                        }
                        FocusClockFace(action: nil) {
                            pomodoroClockContent
                        }
                    }

                    // Left overlay
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            StandardActionButton(title: Localization.get("Stats", lang: appLanguage), icon: "chart.bar.xaxis", tint: interfaceTint, variant: .primary, fillsAvailableWidth: true) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    isShowingStats = true
                                }
                            }
                            StandardActionButton(title: Localization.get("Settings", lang: appLanguage), icon: "slider.horizontal.3", tint: interfaceTint, variant: .primary, fillsAvailableWidth: true) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    isShowingSettings = true
                                }
                            }
                            StandardActionButton(title: Localization.get("Reset", lang: appLanguage), icon: "arrow.counterclockwise", tint: interfaceTint, variant: .primary, fillsAvailableWidth: true) {
                                if pomodoro.hasActiveSession {
                                    isShowingResetConfirmation = true
                                } else {
                                    pomodoro.reset()
                                }
                            }
                        }
                    }

                    // Right overlay
                    HStack(spacing: 8) {
                        VStack(spacing: 6) {
                            if !pomodoro.isRunning {
                                focusModeMenu
                            }
                            if pomodoro.isRunning {
                                StandardActionButton(title: Localization.get("Skip", lang: appLanguage), icon: "forward.end.fill", tint: displayedTint, variant: .primary, fillsAvailableWidth: true) {
                                    pomodoro.skipPhase()
                                }
                            }
                            StandardActionButton(title: Localization.get(pomodoro.isRunning ? "Pause" : "Start", lang: appLanguage), icon: pomodoro.isRunning ? "pause.fill" : "play.fill", tint: interfaceTint, variant: .primary, fillsAvailableWidth: true) {
                                pomodoro.toggleRunning()
                            }
                        }
                    }
                }
```

and:

```swift
    private var focusModeMenu: some View
```

The desired layout needs new view types that do not exist yet, so the initial red step is to wire `PomodoroPanelView` to them before creating them.

- [ ] **Step 2: Run the build red check**

Temporarily replace the main body branch in `PomodoroPanelView` with the target composition:

```swift
            } else {
                FocusMainPanel(
                    pomodoro: pomodoro,
                    displayedPhase: displayedPhase,
                    idleDisplayedSeconds: idleDisplayedSeconds,
                    displayedTint: displayedTint,
                    interfaceTint: interfaceTint,
                    appLanguage: appLanguage,
                    onShowStats: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isShowingStats = true
                        }
                    },
                    onShowSettings: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isShowingSettings = true
                        }
                    },
                    onReset: {
                        if pomodoro.hasActiveSession {
                            isShowingResetConfirmation = true
                        } else {
                            pomodoro.reset()
                        }
                    }
                )
                .offset(y: 8)
                .transition(.opacity)
            }
```

Run:

```bash
swift build --product Notch
```

Expected:

```text
error: cannot find 'FocusMainPanel' in scope
```

- [ ] **Step 3: Add the new panel components and remove the old rail layout**

Create `Sources/Notch/Focus/PomodoroPanelComponents.swift` with the new focused subviews:

```swift
import SwiftUI
import NotchFocusCore

struct FocusMainPanel: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let displayedPhase: PomodoroPhase
    let idleDisplayedSeconds: Int
    let displayedTint: Color
    let interfaceTint: Color
    let appLanguage: String
    let onShowStats: () -> Void
    let onShowSettings: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            FocusHeaderRow(
                pomodoro: pomodoro,
                displayedPhase: displayedPhase,
                tint: displayedTint,
                appLanguage: appLanguage
            )

            FocusHeroTimer(
                pomodoro: pomodoro,
                displayedPhase: displayedPhase,
                idleDisplayedSeconds: idleDisplayedSeconds,
                tint: displayedTint
            )

            FocusTaskLabel(
                title: pomodoro.currentTask,
                tint: displayedTint,
                appLanguage: appLanguage
            )

            FocusCommandDock(
                pomodoro: pomodoro,
                displayedTint: displayedTint,
                interfaceTint: interfaceTint,
                appLanguage: appLanguage,
                onShowStats: onShowStats,
                onShowSettings: onShowSettings,
                onReset: onReset
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
```

Add the command-dock implementation with the state split required by the spec:

```swift
struct FocusCommandDock: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let displayedTint: Color
    let interfaceTint: Color
    let appLanguage: String
    let onShowStats: () -> Void
    let onShowSettings: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if pomodoro.isRunning {
                StandardActionButton(
                    title: Localization.get("Pause", lang: appLanguage),
                    icon: "pause.fill",
                    tint: interfaceTint,
                    variant: .primary
                ) {
                    pomodoro.toggleRunning()
                }

                StandardActionButton(
                    title: Localization.get("Skip", lang: appLanguage),
                    icon: "forward.end.fill",
                    tint: displayedTint,
                    variant: .primary
                ) {
                    pomodoro.skipPhase()
                }
            } else if pomodoro.hasActiveSession {
                StandardActionButton(
                    title: Localization.get("Resume", lang: appLanguage),
                    icon: "play.fill",
                    tint: interfaceTint,
                    variant: .primary
                ) {
                    pomodoro.toggleRunning()
                }
                StandardActionButton(title: Localization.get("Reset", lang: appLanguage), icon: "arrow.counterclockwise", tint: interfaceTint, variant: .secondary, action: onReset)
                StandardActionButton(title: Localization.get("Stats", lang: appLanguage), icon: "chart.bar.xaxis", tint: interfaceTint, variant: .secondary, action: onShowStats)
                StandardActionButton(title: Localization.get("Settings", lang: appLanguage), icon: "slider.horizontal.3", tint: interfaceTint, variant: .secondary, action: onShowSettings)
            } else {
                StandardActionButton(
                    title: Localization.get("Start", lang: appLanguage),
                    icon: "play.fill",
                    tint: interfaceTint,
                    variant: .primary
                ) {
                    pomodoro.toggleRunning()
                }
                StandardActionButton(title: Localization.get("Stats", lang: appLanguage), icon: "chart.bar.xaxis", tint: interfaceTint, variant: .secondary, action: onShowStats)
                StandardActionButton(title: Localization.get("Settings", lang: appLanguage), icon: "slider.horizontal.3", tint: interfaceTint, variant: .secondary, action: onShowSettings)
                StandardActionButton(title: Localization.get("Reset", lang: appLanguage), icon: "arrow.counterclockwise", tint: interfaceTint, variant: .secondary, action: onReset)
            }
        }
    }
}
```

In `Sources/Notch/Music/NotchFocusPanels.swift`, remove:

- the entire left overlay block
- the entire right overlay block
- `focusModeMenu`

Keep the settings/stats sheet toggles and reset alert in `PomodoroPanelView`.

- [ ] **Step 4: Build and visually verify the notch panel compiles**

Run:

```bash
swift build --product Notch
```

Expected:

```text
Build of product 'Notch' complete!
```

Then launch the app and manually verify:

```bash
swift run Notch
```

Expected manual result:

```text
The focus panel opens in the notch with:
- centered phase row
- large timer
- task label under the timer
- running dock showing only Pause and Skip
- paused/idle dock showing utility actions
```

- [ ] **Step 5: Commit the focus-panel redesign**

Run:

```bash
git add Sources/Notch/Music/NotchFocusPanels.swift Sources/Notch/Focus/PomodoroPanelComponents.swift
git commit -m "feat: redesign focus panel for notch-only flow"
```

---

### Task 4: Remove Fullscreen Messaging From User-Facing Docs

**Files:**
- Modify: `Sources/Notch/docs/focus-mechanism.html`
- Test: `Sources/Notch/docs/focus-mechanism.html`

- [ ] **Step 1: Write the failing content diff**

The current doc still advertises fullscreen modes in `Sources/Notch/docs/focus-mechanism.html:502-527` and mentions `Strict` again in `:563-565`.
Replace that section with a notch-only description:

```html
      <section id="modes" data-index="04">
        <div class="section-inner reveal">
          <h2>Không gian làm việc: tập trung ngay trong notch</h2>
          <p>
            Focus không còn tách ra thành một lớp toàn màn hình riêng.
            Thay vào đó, toàn bộ trải nghiệm tập trung sống ngay trong notch mở rộng:
            đồng hồ lớn, task hiện tại, tiến độ chu kỳ và các nút điều khiển đúng ngữ cảnh.
          </p>
          <div class="modes">
            <div class="mode off">
              <h4>Running</h4>
              <p><strong style="color:var(--text)">Lợi ích:</strong> khi phiên đang chạy, giao diện chỉ giữ lại đồng hồ và hai hành động chính là tạm dừng hoặc bỏ qua pha, giúp mắt bớt phân tán.</p>
            </div>
            <div class="mode zen">
              <h4>Paused</h4>
              <p><strong style="color:var(--text)">Lợi ích:</strong> khi tạm dừng, notch mở rộng thêm các nút như tiếp tục, đặt lại, thống kê và cài đặt để bạn điều chỉnh mà không làm rối lúc đang tập trung.</p>
            </div>
            <div class="mode strict">
              <h4>Idle</h4>
              <p><strong style="color:var(--text)">Lợi ích:</strong> trước khi bắt đầu, panel cho bạn thấy thời lượng của pha hiện tại và các công cụ cần thiết để vào phiên nhanh, không cần chuyển sang bề mặt khác.</p>
            </div>
          </div>
        </div>
      </section>
```

Also replace the `Strict` mention in the tips list with:

```html
            <li><strong style="color:var(--text)">Nghỉ rõ ràng theo pha</strong> — khi chuyển sang nghỉ ngắn hoặc nghỉ dài, bạn vẫn thấy trạng thái mới ngay trong notch; không bị đứt nhịp vì một lớp phủ khác chen vào.</li>
```

- [ ] **Step 2: Run a targeted grep check**

Run:

```bash
rg -n "Zen|Strict|toàn màn hình|fullscreen" Sources/Notch/docs/focus-mechanism.html
```

Expected:

```text
(no matches)
```

- [ ] **Step 3: Apply the doc edit**

Update the HTML exactly as above and keep the surrounding section structure intact.

- [ ] **Step 4: Re-run the grep check**

Run:

```bash
rg -n "Zen|Strict|toàn màn hình|fullscreen" Sources/Notch/docs/focus-mechanism.html
```

Expected:

```text
(no matches)
```

- [ ] **Step 5: Commit the doc cleanup**

Run:

```bash
git add Sources/Notch/docs/focus-mechanism.html
git commit -m "docs: update focus mechanism for notch-only design"
```

---

### Task 5: Final Verification Pass

**Files:**
- Modify: none
- Test: `Tests/NotchFocusTests/main.swift`
- Test: `Sources/Notch/Music/NotchFocusPanels.swift`
- Test: `Sources/Notch/Window/NotchWindowController.swift`
- Test: `Sources/Notch/docs/focus-mechanism.html`

- [ ] **Step 1: Run the core regression suite**

Run:

```bash
swift run NotchFocusTests
```

Expected:

```text
========== NotchFocusTests summary ==========
11/11 passed, 0 failed
```

- [ ] **Step 2: Run the app build**

Run:

```bash
swift build --product Notch
```

Expected:

```text
Build of product 'Notch' complete!
```

- [ ] **Step 3: Do the manual UI verification**

Launch:

```bash
swift run Notch
```

Expected manual checklist:

```text
1. Open Focus panel from the notch switcher.
2. Confirm no fullscreen overlay appears when starting a session.
3. Confirm running state shows only Pause and Skip.
4. Confirm paused state shows Resume, Reset, Stats, Settings.
5. Confirm idle state shows Start, Reset, Stats, Settings.
6. Confirm reset confirmation still appears for active sessions.
7. Confirm stats and settings overlays still open and close correctly.
```

- [ ] **Step 4: Review the final diff**

Run:

```bash
git status --short
git diff --stat
```

Expected:

```text
Modified files are limited to:
- Sources/NotchFocusCore/PomodoroViewModel.swift
- Sources/Notch/Music/NotchFocusPanels.swift
- Sources/Notch/Focus/PomodoroPanelComponents.swift
- Sources/Notch/Window/NotchWindowController.swift
- Sources/Notch/docs/focus-mechanism.html
- Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift
- Tests/NotchFocusTests/main.swift
- Sources/Notch/Focus/PomodoroFullscreenWindowController.swift (deleted)
```

- [ ] **Step 5: Commit the verified feature**

Run:

```bash
git add Sources/NotchFocusCore/PomodoroViewModel.swift Sources/Notch/Music/NotchFocusPanels.swift Sources/Notch/Focus/PomodoroPanelComponents.swift Sources/Notch/Window/NotchWindowController.swift Sources/Notch/docs/focus-mechanism.html Tests/NotchFocusTests/PomodoroViewModelP0Tests.swift Tests/NotchFocusTests/main.swift Sources/Notch/Focus/PomodoroFullscreenWindowController.swift
git commit -m "feat: redesign focus panel without fullscreen"
```
