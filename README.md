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
- **Two swipe gestures, disambiguated by the thumb** (like the native trackpad feel):
  - **4 fingers, thumb tucked → page swipe** — switch Space, windows stay put (green feedback).
  - **All 5 fingers, thumb splayed → window swipe** — carry the focused window across to the adjacent Space (blue feedback).

  Detection is **displacement-over-a-time-window** (the hand must travel a set distance within N ms), not instantaneous velocity — robust to frame-rate and brief tracking dropouts, and it won't false-trigger on slow drift. A live progress bar + finger/thumb readout shows which gesture is arming.
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

A Swift menu-bar app carrying over the tuned constants: `AVFoundation` capture → Vision `VNDetectHumanHandPoseRequest` for landmarks → Accessibility API (`AXUIElement`) to move real windows → `CGEvent` for Space switching. Per-display click-through overlay windows and live window-under-pointer highlighting.

### Multi-monitor pointer mapping (design)

The hard problem on a multi-monitor setup: a comfortable in-air hand range is small, but the desktop can be very wide. Mapping the whole hand range across the full multi-display bounding box (naive absolute mapping) destroys precision — a twitch throws the pointer across three screens. Mapping it to one display makes the others unreachable.

**Chosen approach: per-display absolute mapping + a clutched, animated hand-off at monitor seams.** This matches the "remap each time you jump monitors, but keep it smooth" idea.

1. **Absolute within the active display.** The calibrated comfortable hand range (from the pinch-corner calibration) maps 1:1 to the *current* display's bounds only. Full precision, predictable "point where you mean" feel — you get the whole hand range for one screen instead of spreading it thin across all of them.

2. **Push-to-cross hand-off (the clutch).** Displays know their neighbors from the arrangement topology (`NSScreen.frame` in the global coordinate space — handles horizontal, vertical, and offset/mismatched-size layouts). When the pointer reaches an edge that borders another display and the hand keeps pushing past it, it must clear an **edge-pressure threshold** — travel a bit beyond the edge *or* dwell against it for a few frames (hysteresis) — before the hand-off commits. That gate stops accidental screen jumps. Committing the cross **re-anchors** the mapping so the hand's current position now corresponds to the *entry edge* of the new display. Re-anchoring is the clutch: each monitor effectively gets the full hand range, so you never run out of reach mid-desktop.

3. **Smooth seam transition.** During a hand-off the pointer is briefly *animated* across the physical gap between the two displays (a short eased tween, matched to the overlay's existing cursor animation) rather than teleporting, and y is aligned to where the pointer was so it doesn't jump vertically when displays are offset. Reads as one continuous glide across the seam.

4. **Optional explicit clutch gesture.** A dedicated "freeze" gesture (candidate: closed fist, or a held two-finger pause) that pins the pointer so you can recenter your arm without moving it — exactly like lifting a mouse off the desk — then re-engage. Useful for long reaches and as a manual way to settle before a precise grab. To be prototyped for feel before committing.

**Alternative kept in reserve — pure relative / trackpad mode:** pointer moves by hand *delta* with velocity-adaptive gain (slow = fine, fast = coarse), clutch = fist-and-reposition. Spans all monitors with zero seam logic, but loses the absolute point-where-you-look feel. Offer as a toggle if the absolute+hand-off model feels too constrained in testing.

Calibration feeds this directly: the pinch-at-top-left / pinch-at-bottom-right step sets the comfortable hand range that maps to *each* display, and is re-runnable from the menu bar.

> Worth prototyping the seam hand-off + clutch feel in the Phase 1 web rig first — a single wide canvas can simulate two side-by-side "monitors" so the interaction is validated before writing the `NSScreen`/overlay plumbing. Say the word and I'll add it.

Out of scope for Phase 2 v1: multi-user profiles, custom gesture training, iOS companion, window resizing (move only), anything requiring network access.

---

Personal, single-user tool. Local-only by design.
