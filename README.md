# AirControl

Control macOS windows and virtual desktops with in-air hand gestures captured by the MacBook webcam — no trackpad, no keyboard. Pinch in the air to grab and drag a window; point your thumb to switch Spaces. Runs entirely on-device: no cloud, no accounts, no telemetry.

## Install (no developer tools needed)

Works on any Mac running macOS 14 (Sonoma) or newer.

1. **[Download AirControl-0.2.0.dmg](https://github.com/RonakToprani/aircontrol/releases/latest)** and open it, then drag **AirControl** into **Applications**.
2. Open AirControl from Applications. macOS will block it the first time (this test build isn't notarized) — go to **System Settings → Privacy & Security**, scroll down, click **"Open Anyway"**, and confirm.
3. AirControl lives in the **menu bar** (hand icon, top-right — no Dock icon). Click it → **Enable AirControl**, and allow **Camera** access.
4. When the **Accessibility** prompt appears: it only *opens* System Settings — you must flip the AirControl switch there yourself (this is how it moves windows).
5. Click the hand icon → **Calibrate hand range…** and follow the on-screen guide. Done — see the gesture table below.

| Gesture | Action |
|---|---|
| Move open hand | Move the cursor |
| Pinch (thumb + index) on a window | Grab it; move to drag; release to drop |
| Fist + thumb pointing left/right, hold | Switch desktop/Space in that direction |
| Peace sign ✌, hold | Turn AirControl off (turn back on from the menu bar) |

**Mouse mode** (menu bar → *Mouse mode — pinch to click*, or hold a shaka 🤙): your hand drives the *real* macOS cursor instead (the system arrow hides — the teal ring is the cursor) — pinch = left click, pinch-hold = drag, two quick pinches = double-click, and a single pinch on a Finder file or desktop icon opens it. Close your hand into a fist (thumb tucked in) to grab the page and scroll, with momentum. Window grabbing pauses while it's on (pinch-drag a title bar to move a window, like a mouse would).

| Mouse-mode gesture | Action |
|---|---|
| Shaka 🤙 (thumb + little out), hold | Toggle mouse mode on/off — indigo meter fills |
| Pinch (thumb + index) | Left click; hold and move to drag; on a file icon, opens it |
| Fist (thumb tucked in) | Grab the page and scroll; open to release and coast |
| Pinch-hold still on a text box | Dictate — mic listens while you hold (orange ring), release types it |
| Pinch + tilt hand down, release | Press Enter/send (green ring shows "release to send"; tilt back up to cancel) |

##  Native macOS App - Version 3 (current)

The working app lives in **[`app/`](app/)** — a menu-bar-only Swift app (no Dock icon): `AVFoundation` capture → Vision `VNDetectHumanHandPoseRequest` at ~30fps → 1€-filtered landmarks → the ported Phase 1 gesture engine → click-through overlay with 60fps render-easing → Accessibility API to move real windows → `CGEvent` for Space switching. The full design rationale is in **[PLAN.md](PLAN.md)**.

### Building & running

Requirements: macOS 14+, Xcode (or Command Line Tools) with Swift 5.9+.

```bash
cd app
make run
```

`make run` does everything: `swift build -c release`, assembles `build/AirControl.app` with `Info.plist`, codesigns, and launches. Signing prefers an installed **Apple Development** identity so the camera + Accessibility permission grants survive rebuilds (falls back to ad-hoc, but then macOS revokes grants on every rebuild). Other targets: `make build` (binary only), `make bundle` (app bundle without launching), `make clean`.

First run, grant two permissions:

1. **Camera** — prompted automatically when you enable AirControl.
2. **Accessibility** (moves windows, posts Space-switch keys) — the prompt only *opens* System Settings; you must flip the AirControl toggle there yourself. The tuning panel shows a live granted/NOT-GRANTED readout plus test buttons.

Space switching posts the default Mission Control shortcuts (⌃← / ⌃→) — they must be enabled in System Settings › Keyboard › Shortcuts.

### Using it

Click the hand icon in the menu bar → **Enable AirControl**.

| Gesture | Action |
|---|---|
| Move open hand | Move the overlay pointer (whole desktop, all displays) |
| Pinch (thumb–index) | Grab the window under the pointer (raises it, like a click); move to drag; release to drop |
| Fist + thumb pointing left/right, hold ~300ms | Switch Space in that direction, on the display the pointer is on |

**Mouse mode** (menu-bar toggle or shaka 🤙 hold, persisted): the eased pointer drives the real macOS cursor via `CGEvent` — pinch = left mouse down, hold = drag (with a click-vs-drag slop so jitter stays a clean click), release = up; successive pinches in place escalate the click count (double/triple-click), and a clean pinch on a Finder file item auto-double-clicks so one pinch opens it. A fist with the thumb tucked grabs the page to scroll (pixel wheel events, momentum coast) — thumb tucked = scroll, thumb out sideways = Space switch, thumb out + little up = shaka. Pinch-holding still on a text field is push-to-talk dictation: the mic is live only while the pinch is held, recognition is Apple's on-device engine (audio never leaves the Mac), the live transcript shows in the HUD, and release types the result. Pinch + tilt the hand down + release presses Return — but only when a text field has focus; it works mid-dictation or later, after you've read the text over. The system cursor hides while on — the ring is the cursor. Window grab/hover is suspended so a pinch means exactly one thing. Uses the same Accessibility permission as Space switching.

**Calibrate hand range…** (menu bar) is strongly recommended: pinch-hold at your comfortable top-left, then bottom-right — that box then maps to the whole desktop, so you never stretch. Re-run any time you change seating position; **Reset calibration** returns to the default camera margin.

**Show tuning panel** exposes every constant as a live slider (smoothing, pinch thresholds, drag precision, Space-switch hold time, AX write rate, …) with live diagnostics (detect FPS, pinch distance, gesture state, AX write latency). Tune by feel; values persist.

Out of scope for Phase 2 v1: multi-user profiles, custom gesture training, iOS companion, window resizing (move only — planned for v2 as a two-handed gesture), anything requiring network access.

---

Personal, single-user tool. Local-only by design.
