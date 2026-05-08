# Tuesday Night Timer

A Garmin Connect IQ sailing race timer for fenix smartwatches (fenix 5/6/7 series). Implements the ISAF Rule 26 warning sequence with precise haptic feedback, helmsman sync-to-horn feature, integrated stopwatch, and automatic activity recording.

## Domain Context: Sailing Race Signals

In organized sailing (PHRF, ORC handicap races), the starting sequence follows [ISAF Rule 26](https://www.world-sailing.org/documents-and-links/rules/):

- **T-5:00** (5 minutes before start): First warning signal (horn) — skippers begin maneuvering
- **T-4:00** (4 minutes): Second warning signal — preparation horn
- **T-1:00** (1 minute): Final warning signal — last chance to reach starting line
- **T-0:00** (at start): Start signal (gun) — race begins

Before the race, competitors hear a physical horn on the water (air horn, whistle, etc.). This app vibrates the watch at each of these moments, giving helmsmen haptic feedback even in noisy conditions.

The **sync feature** allows a helmsman to hear the physical horn and then press the center button within a 10-second window to snap the watch to that exact signal. This is critical for coordinating multiple boats and avoiding watch drift on the starting line.

## Features

### Timer
- Countdown from configurable start times (5, 4, 3, 2, 1 minute presets)
- Wall-clock synchronization (not timer-count) to survive background suspension
- Haptic warnings:
  - Major horns: long vibration (100ms at 800ms duration)
  - Final countdown (10–1 seconds before each horn and start): short ticks (100ms at 150ms)
  - Start gun: double-burst (800ms–gap–800ms)

### Sync-to-Horn
- 10-second sync window before each warning horn and the final 10 seconds before the start gun
- Helmsman presses center button (long-hold, 700ms) to show green overlay
- Release snaps the watch to the last horn that was at or before the press moment
- Allows correction if the watch drifted or the helmsman was late to hear the signal

### Stopwatch
- Independent of race timer: runs in parallel
- Start/pause/reset cycle via short center button press (outside sync window)
- Centisecond display (hundredths of a second): **M:SS:CS**
- ~10 Hz UI refresh for smooth animation

### Activity Recording
- Automatically records the race as a fitness activity (sport: Boating, subSport: Generic)
- Captures Speed Over Ground (SOG) and Course Over Ground (COG) from watch sensors
- Can save or discard the activity after the race
- REC indicator blinks (1 Hz) while recording

### Input Controls

| Button | Action | Context |
|--------|--------|---------|
| **CENTER** (short press) | Start race / Cycle stopwatch | READY state or while RUNNING |
| **CENTER** (long-hold, 700ms) | Sync to horn (green overlay) | RUNNING + in sync window |
| **CENTER** (release) | Confirm sync snap or cycle stopwatch | Depends on state |
| **DOWN** (double-press) | Emergency exit | While RUNNING |
| **UP** (page cycle) | Toggle racing screen (COG ↔ elapsed) | While recording |
| **MENU** | Open start time picker / Reset race | READY state or while RUNNING |
| **BACK** | Reset and return to READY | FINISHED state |

## Architecture

The codebase is structured into focused classes:

### RaceEngine.mc
Pure timing and haptics logic — no drawing.

- **States**: READY, RUNNING, FINISHED
- **Core methods**:
  - `start()` — begin race countdown
  - `processWallClockSeconds()` — advance haptics by wall-clock (catches up after suspension)
  - `enterSyncMode()` / `finishSync()` / `cancelSync()` — sync protocol
  - `triggerHaptics()` — vibration and backlight control
- **Key insight**: Uses `System.getTimer()` as anchor, not callback counting. CIQ suspends the process in the background, so callbacks are missed. `onShow()` re-enters and replays missed seconds.

### Stopwatch.mc
Independent stopwatch with its own state machine.

- **States**: IDLE, RUNNING, PAUSED
- **Methods**: `cycle()` (state transitions), `formatDisplay()` (M:SS:CS)
- **UI timer**: 100ms (~10 Hz) for smooth centisecond animation

### ActivityManager.mc
Wrapper around Garmin's ActivityRecording API.

- **Lifecycle**: `startSession()` → optional `saveSession()` or `discardSession()`
- **REC indicator**: blinks at 1 Hz via internal timer
- **Error handling**: silently ignores missing API on devices without ActivityRecording

### Tuesday_Night_TimerView.mc (trimmed)
Orchestration and rendering. Delegates all logic to engines.

- **Holds**: instances of RaceEngine, Stopwatch, ActivityManager
- **Responsibility**: `onLayout()`, `onShow()`, `onUpdate()`, all `draw*()` methods
- **Lifecycle**: manages idle timeout (5-hour auto-exit), race timer, UI timers
- **Public interface**: thin pass-through methods for Delegate (e.g., `isRunning()`, `cycleStopwatch()`)

### Tuesday_Night_TimerDelegate.mc
Low-level and high-level input handling.

- **Receives**: `onKeyPressed()`, `onKeyReleased()`, `onKey()` (physical), plus `onSelect()`, `onBack()`, `onMenu()` (high-level)
- **Logic**: maps gestures (long-hold, double-press, short-release) to actions
- **Quirk handling**: suppresses duplicate `onSelect()` calls to avoid double-cycling stopwatch

### Supporting Delegates
- **Tuesday_Night_TimerMenuDelegate**: callback wrapper for start-time menu selection
- **Tuesday_Night_TimerConfirmDelegate**: yes/no confirmation for immediate exit
- **Tuesday_Night_TimerSaveDelegate**: save/discard/keep racing choice for activity

## Supported Devices

Fenix 5/6/7 series with Activity Recording API:
- fenix 5s, 5s+, 5x+
- fenix 6, 6 Pro, 6s, 6s Pro, 6x Pro
- fenix 7, 7s, 7x, 7 Pro, 7x Pro
- fenix Chronos

## Building

1. Install [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/start/)
2. Open in VS Code with the official **Monkey C** extension
3. Build: `Monkey C: Build` from the command palette
4. Run on simulator or sideload to device

## Notes for Portfolio

This project demonstrates:

- **Non-standard library expertise**: Deep integration with Garmin's Toybox API (Activity, ActivityRecording, Attention, Timer, WatchUi)
- **Sophisticated state machines**: Race countdown, stopwatch, and activity recording with strict state transitions
- **Platform constraints & workarounds**: Handling CIQ's process suspension, SDK SDK quirks (onSelect firing between key events), platform-specific capability checks (`:vibrate`, `:backlight`, `:ActivityRecording`)
- **Precision timing**: Wall-clock synchronization across background suspension to maintain haptic replay accuracy
- **Domain-specific knowledge**: Understanding ISAF sailing rules and implementing realistic sync protocol
- **Clean architecture**: Separated concerns (engine, stopwatch, activity manager) with thin orchestration layer

## License

Personal project.
