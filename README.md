# AirControl

Control macOS windows and virtual desktops with in-air hand gestures captured by the MacBook webcam — no trackpad, no keyboard. Pinch in the air to grab and drag a window; open-palm sweep to switch Spaces. Runs entirely on-device: no cloud, no accounts, no telemetry.

Built in two phases.

## Phase 1 — Gesture Feel Prototype ✅ (this commit)

A single self-contained web page for validating hand-tracking accuracy, gesture recognition, coordinate mapping, and cursor-overlay *feel* before any native code is written.

- **[`phase1/index.html`](phase1/index.html)** — open in Chrome, grant camera access, start gesturing.

Uses [MediaPipe Hands](https://developers.google.com/mediapipe) (JS/WASM) for 21-landmark hand pose. This is the prototype's only external dependency, loaded once from the jsDelivr CDN — bundling the WASM model into a single HTML file is impractical. Phase 2 replaces it with Apple's on-device Vision framework, where the strict "no network" constraint applies.

### What it does
- Live webcam feed with a custom canvas cursor overlay (no OS cursor involved).
- **Pinch** (thumb tip ↔ index tip, normalized by hand size so it works at any distance) to grab and drag mock windows; release to drop. The grab point stays fixed relative to the window.
- **Open palm + lateral sweep** switches between two mock Spaces, with a cooldown so one sweep fires once. Verified not to false-trigger against pinch.
- **EMA smoothing** on both cursor position and the pinch signal, with pinch **hysteresis** to stop threshold flicker.
- **Coordinate mapping** from normalized webcam space to screen space with a configurable edge margin (dead-zone), so you never have to reach the literal frame edge.
- Cursor states — idle ring → hover highlight → filled pinch dot — with smooth animated transitions, plus a targeting-style highlight border on the window about to be grabbed (previews the real Phase 2 behavior).
- A live **tuning panel**: every constant (smoothing α, pinch threshold + hysteresis, margin, swipe velocity + cooldown, palm-extension threshold) is a slider. Nothing is hardcoded — tune by feel, then carry the numbers into Phase 2.

### Running
Open `phase1/index.html` directly in a modern browser (Chrome recommended). Click **Enable Camera & Start** and grant camera permission. No backend, no build step.

Keyboard: `H` toggles help · `P` toggles the tuning panel.

### Tuning constants
All defaults live in one place — the `DEFAULTS` object at the top of the `<script>` in `phase1/index.html` — and each is bound to a panel slider. When the feel is dialed in, these values transfer directly to the Phase 2 Swift `Config`.

## Phase 2 — Native macOS App (not yet built)

A Swift menu-bar app carrying over the tuned constants: `AVFoundation` capture → Vision `VNDetectHumanHandPoseRequest` for landmarks → Accessibility API (`AXUIElement`) to move real windows → `CGEvent` for Space switching. Multi-monitor coordinate mapping with a re-runnable pinch calibration, per-display click-through overlay windows, and live window-under-pointer highlighting.

Out of scope for Phase 2 v1: multi-user profiles, custom gesture training, iOS companion, window resizing (move only), anything requiring network access.

---

Personal, single-user tool. Local-only by design.
