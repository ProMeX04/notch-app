# Focus Redesign Without Fullscreen

## Summary

Redesign the `focus` panel so the expanded notch panel becomes the only focus surface.
Remove fullscreen-related behavior entirely.
Adopt a timer-first layout with a compact command dock that changes by session state.

## Context

The current focus experience is split across two surfaces:

- The notch panel (`PomodoroPanelView`) for routine interaction
- A separate fullscreen overlay (`PomodoroFullscreenWindowController`) driven by `Off / Zen / Strict`

That split creates three problems:

1. The focus UI has two competing mental models.
2. `focusMode` and `isFullscreenActive` add state complexity to the core timer flow.
3. The current notch panel is functional but visually fragmented, with controls distributed into left/right side rails instead of a single strong focal hierarchy.

## Goals

- Make the expanded notch panel the single, canonical focus experience.
- Shift the visual hierarchy to timer-first.
- Keep the running state visually calm and low-distraction.
- Preserve existing timer behavior, session progression, stats, and settings.
- Remove fullscreen-related code paths and user-facing mode concepts.

## Non-Goals

- No change to pomodoro timing rules, presets, or stats logic.
- No new focus modes replacing `Off / Zen / Strict`.
- No redesign of unrelated panels (`media`, `talk`, `shelf`, `settings`).
- No attempt to introduce a separate detached window or larger focus workspace.

## Approaches Considered

### 1. Lean Runtime

Running state shows only the essential controls (`Pause`, `Skip`) beneath a large timer.
Idle and paused states reveal utility actions such as `Start/Resume`, `Settings`, `Stats`, and `Reset`.

Pros:

- Best match for the requested timer-first direction
- Strongest reduction in visual noise while a session is active
- Clean conceptual replacement for fullscreen: focused, but still inside the notch

Cons:

- Utility actions take one extra step during active runs

### 2. Persistent Dock

Keep a full dock visible at all times, but visually emphasize only primary actions.

Pros:

- Highest action availability
- Easier for power users who frequently jump between controls

Cons:

- Weakens the timer-first hierarchy
- Conflicts with the explicit request to keep only `Pause` and `Skip` while running

### 3. Split States

Running state uses a minimal dock; paused state expands to show broader utilities.

Pros:

- Balanced compromise between calm running UI and broader paused controls

Cons:

- Higher UI-state complexity
- Increased layout shifting between active states

## Chosen Direction

Use **Lean Runtime**.

This direction best matches the requested outcome:

- notch-native presentation
- command-dock visual language
- timer-first hierarchy
- `Pause + Skip` only while running
- fullscreen removed instead of replaced

## UX Design

### Shared Layout

The expanded focus panel uses one centered vertical stack:

1. Small phase/status row at the top
2. Large timer in the center
3. Current task directly associated with the timer
4. Bottom command dock

The phase row stays compact and informational rather than decorative.
It should communicate:

- current phase (`Focus`, `Short Break`, `Long Break`)
- cycle progress (`Round x/y` or dots)

The timer remains the dominant element in all focus states.
The task label is secondary, directly under or beside the timer depending on spacing, but always visually subordinate to the clock.

### Running State

Running is the calmest state.

Display:

- phase/status row
- large live timer
- current task, if present
- dock with only:
  - `Pause`
  - `Skip`

Do not show `Stats`, `Settings`, `Reset`, or focus mode controls while actively running.

### Paused State

Paused keeps the same overall layout, but the dock expands to utility actions.

Display:

- phase/status row
- timer with paused time
- current task
- dock with:
  - `Resume`
  - `Reset`
  - `Stats`
  - `Settings`

### Idle State

Idle should feel ready, not empty.

Display:

- phase/status row
- static timer for the selected phase
- current task if selected
- dock with:
  - `Start`
  - `Stats`
  - `Settings`
  - `Reset`

If there is no active task, the layout should remain balanced without introducing placeholder clutter.

### Overlay Panels

Existing settings and stats views remain available, but are entered from the redesigned dock instead of the current side-rail layout.
Their internal content does not need a broad redesign in this change.

## Fullscreen Removal

Fullscreen is removed as both a feature and an architectural concept.

### In Scope

- Delete `PomodoroFullscreenWindowController`
- Remove `isFullscreenActive` from `PomodoroViewModel`
- Remove `focusMode` and the `PomodoroFocusMode` enum
- Remove `exitFullscreen()` and fullscreen evaluation logic
- Remove fullscreen-driven visibility syncing from `NotchWindowController`
- Remove the focus-mode menu from the focus panel UI

### Persistence / Migration

Existing stored focus mode data may remain in `UserDefaults` unused.
No explicit migration is required because:

- the removed value is non-critical
- the new UI no longer reads it
- leaving the stale key is harmless

If the implementation naturally centralizes settings cleanup, removing the stale key is acceptable but not required.

### Documentation

Update or remove references to `Zen`, `Strict`, and fullscreen focus behavior in any shipped docs that describe the feature, especially:

- `Sources/Notch/docs/focus-mechanism.html`

## Technical Design

### View Layer

Refactor `PomodoroPanelView` away from the current three-area layout:

- left control rail
- center clock block
- right control rail

Replace it with a single center-weighted composition and a state-driven command dock.

Recommended decomposition:

- `PomodoroPanelView`
  - orchestration and panel-state switching
- `FocusHeaderRow`
  - phase + round/dots
- `FocusHeroTimer`
  - live/static timer rendering
- `FocusTaskLabel`
  - current task presentation
- `FocusCommandDock`
  - state-based action row

Exact component names may vary, but responsibilities should stay narrow.

### View Model

`PomodoroViewModel` should only model timer/session behavior after this redesign.

It should no longer own presentation concerns tied to fullscreen entry/exit rules.

The remaining state transitions of interest are:

- idle -> running
- running -> paused
- paused -> running
- any state -> reset
- phase transition -> next phase

### Windowing

`NotchWindowController` should always keep focus within the notch window.
No separate panel should hide or replace the notch for pomodoro use.

## Error Handling / Edge Cases

- `Skip` must continue to respect current phase transition rules.
- `Reset` must still ask for confirmation when clearing an active session.
- Pausing and resuming must not alter task/session counters unexpectedly.
- Layout must remain stable when there is no selected task.
- Layout must remain readable for all phases and accent colors already supported by the app.

## Testing Strategy

### Automated

Add or update targeted tests around behavior affected by fullscreen removal:

- `PomodoroViewModel` no longer exposes fullscreen state or mode transitions
- start / pause / resume / skip / reset behavior remains unchanged
- persistence still restores active or paused sessions correctly

If no current tests cover removed fullscreen behavior, prefer deleting obsolete references rather than replacing them with shallow tests.

### Manual

Verify:

1. Focus panel opens and renders the new centered layout.
2. Running state shows only `Pause` and `Skip`.
3. Paused state exposes `Resume`, `Reset`, `Stats`, and `Settings`.
4. Idle state exposes `Start`, `Reset`, `Stats`, and `Settings`.
5. Stats/settings overlays still open and close correctly.
6. Reset confirmation still appears for active sessions.
7. No fullscreen overlay appears under any focus interaction.

## Scope Check

This work fits in a single implementation plan:

- one focused UI redesign
- one bounded feature removal
- limited documentation cleanup

It should not be expanded into a broader pomodoro feature rewrite.
