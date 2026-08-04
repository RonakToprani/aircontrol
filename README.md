# AirControl

Control macOS windows and virtual desktops with in-air hand gestures captured by the MacBook webcam — no trackpad, no keyboard. Pinch in the air to grab and drag a window; four-finger sweep to switch windows/Spaces. Runs entirely on-device: no cloud, no accounts, no telemetry.

Built in phases: **Phase 1** (gesture feel) ✅ → **Phase 1.5** (multi-display mapping) ⚠️ inconclusive → **Phase 2** (native macOS app — see **[PLAN.md](PLAN.md)**).

## Phase 1 — Gesture Feel Prototype ✅

A single self-contained web page for validating hand-tracking accuracy, gesture recognition, coordinate mapping, and cursor-overlay *feel* before any native code is written.

- **[`phase1/index.html`](phase1/index.html)** — open in Chrome, grant camera access, start gesturing.

Uses [MediaPipe Hands](https://developers.google.com/mediapipe) (JS/WASM) for 21-landmark hand pose. This is the prototype's only external dependency, loaded once from the jsDelivr CDN — bundling the WASM model into a single HTML file is impractical. Phase 2 replaces it with Apple's on-device Vision framework, where the strict "no network" constraint applies.

### What it does
- Live webcam feed with a custom canvas cursor overlay (no OS cursor involved).
- **Pinch** (thumb tip ↔ index tip, normalized by hand size so it works at any distance) to grab and drag mock windows; release to drop. The grab point stays fixed relative to the window.
- **Four-finger swipe** left/right switches between windows/Spaces. Detection is **displacement-over-a-time-window** (four fingers must travel a set distance within N ms), not instantaneous velocity — robust to frame-rate and brief tracking dropouts, and it won't false-trigger on slow drift. A live progress bar + finger-count readout shows the gesture arming.
- **Smooth motion by design.** The cursor and any dragged window are eased toward the latest hand position **every render frame (~60fps)**, decoupled from the slower, variable camera detection rate — so dragging glides instead of stepping. Grabbed windows get a subtle lift/shadow animation on pickup and drop.
- **EMA smoothing** on both cursor position and the pinch signal, with pinch **hysteresis** to stop threshold flicker.
- **Coordinate mapping** from normalized webcam space to screen space with a configurable edge margin (dead-zone), so you never have to reach the literal frame edge.
- Cursor states — idle ring → hover highlight → filled pinch dot — with smooth animated transitions, plus a targeting-style highlight border on the window about to be grabbed (previews the real Phase 2 behavior).
- A live **tuning panel**: every constant (smoothing α, pinch threshold + hysteresis, margin, swipe velocity + cooldown, palm-extension threshold) is a slider. Nothing is hardcoded — tune by feel, then carry the numbers into Phase 2.

### Running
Open `phase1/index.html` directly in a modern browser (Chrome recommended). Click **Enable Camera & Start** and grant camera permission. No backend, no build step.

Keyboard: `H` toggles help · `P` toggles the tuning panel.

### Tuning constants
All defaults live in one place — the `DEFAULTS` object at the top of the `<script>` in `phase1/index.html` — and each is bound to a panel slider. When the feel is dialed in, these values transfer directly to the Phase 2 Swift `Config`.

**See [`phase1/TUNING.md`](phase1/TUNING.md)** for a full guide: what each parameter does, the symptom → fix table, and starting recipes for smooth dragging vs. precise pointing vs. reliable swipes.

## Phase 1.5 — Multi-Display Mapping Rig ⚠️

> **Status: inconclusive.** In practice the rig felt bad, but a post-mortem found the causes were implementation defects (a fist-clutch that reads as a pinch, edge-dwell hand-offs with no lockout, the knuckle drag-driver dropped, ~7fps detection, tiny simulated monitors) — not evidence against any mapping model. The mapping decision moves to a bake-off on real displays inside the native app; see **[PLAN.md](PLAN.md)** §1 and §5. The rig is kept below for reference.

A decision tool: **how should an in-air hand map onto a multi-monitor desktop?** A comfortable hand range is small; the desktop can be very wide. Rather than guess, this rig simulates 2–3 monitors on one screen and lets you *feel* three candidate mapping models side-by-side, then pick one before writing any native `NSScreen`/overlay code in Phase 2.

- **[`phase1.5/index.html`](phase1.5/index.html)** — open in Chrome, grant camera, switch models live from the panel (or keys `1`/`2`/`3`).

Carries over Phase 1's validated feel: index-**fingertip** pointer, 60fps render easing, pinch-to-grab, 4-finger swipe, and the tuned constants.

**Three mapping models to compare:**

1. **Direct absolute** — the hand range spans the *whole* desktop bounding box. Baseline, so you can feel exactly why naive absolute mapping is too imprecise on a wide setup.
2. **Per-display + clutch** *(the README's chosen model)* — the hand maps absolutely within the **active display** (full precision, one screen's worth of range). Cross to a neighbor by **dwelling at the shared edge** (an edge-pressure meter fills, then an animated hand-off glides the pointer across the physical gap and re-anchors so your hand's position = the new display's entry edge). Or **4-finger swipe** to jump straight to the next display. **Make a fist to clutch**: freezes the pointer so you can reposition your arm, then open your hand to re-engage — exactly like lifting a mouse to recenter.
3. **Relative + clutch** — trackpad style: the pointer moves by hand *delta* with velocity-adaptive gain (slow = fine, fast = coarse). Spans all monitors with no seam logic; fist to clutch/reposition.

**Simulated layouts:** Laptop + Ultrawide (asymmetric, vertically offset — the hard case), Dual 27″, and Triple. Displays live in a virtual "world" coordinate space that stands in for macOS's global display coordinates; the mapping math is identical to what Phase 2 will use against real `NSScreen` frames.

**What to report back:** which model feels right (or which blend), and tuned values for edge-dwell time and relative gain. That decision drives the Phase 2 mapping implementation.

## Phase 2 — Native macOS App (current)

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

**Calibrate hand range…** (menu bar) is strongly recommended: pinch-hold at your comfortable top-left, then bottom-right — that box then maps to the whole desktop, so you never stretch. Re-run any time you change seating position; **Reset calibration** returns to the default camera margin.

**Show tuning panel** exposes every constant as a live slider (smoothing, pinch thresholds, drag precision, Space-switch hold time, AX write rate, …) with live diagnostics (detect FPS, pinch distance, gesture state, AX write latency). Tune by feel; values persist.

Out of scope for Phase 2 v1: multi-user profiles, custom gesture training, iOS companion, window resizing (move only — planned for v2 as a two-handed gesture), anything requiring network access.

---

Personal, single-user tool. Local-only by design.
