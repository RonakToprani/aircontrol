# AirControl

Control macOS windows and virtual desktops with in-air hand gestures captured by the MacBook webcam — no trackpad, no keyboard. Pinch in the air to grab and drag a window; four-finger sweep to switch windows/Spaces. Runs entirely on-device: no cloud, no accounts, no telemetry.

Built in phases: **Phase 1** (gesture feel) ✅ → **Phase 1.5** (multi-display mapping) ✅ → **Phase 2** (native macOS app).

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

## Phase 1.5 — Multi-Display Mapping Rig ✅

A decision tool: **how should an in-air hand map onto a multi-monitor desktop?** A comfortable hand range is small; the desktop can be very wide. Rather than guess, this rig simulates 2–3 monitors on one screen and lets you *feel* three candidate mapping models side-by-side, then pick one before writing any native `NSScreen`/overlay code in Phase 2.

- **[`phase1.5/index.html`](phase1.5/index.html)** — open in Chrome, grant camera, switch models live from the panel (or keys `1`/`2`/`3`).

Carries over Phase 1's validated feel: index-**fingertip** pointer, 60fps render easing, pinch-to-grab, 4-finger swipe, and the tuned constants.

**Three mapping models to compare:**

1. **Direct absolute** — the hand range spans the *whole* desktop bounding box. Baseline, so you can feel exactly why naive absolute mapping is too imprecise on a wide setup.
2. **Per-display + clutch** *(the README's chosen model)* — the hand maps absolutely within the **active display** (full precision, one screen's worth of range). Cross to a neighbor by **dwelling at the shared edge** (an edge-pressure meter fills, then an animated hand-off glides the pointer across the physical gap and re-anchors so your hand's position = the new display's entry edge). Or **4-finger swipe** to jump straight to the next display. **Make a fist to clutch**: freezes the pointer so you can reposition your arm, then open your hand to re-engage — exactly like lifting a mouse to recenter.
3. **Relative + clutch** — trackpad style: the pointer moves by hand *delta* with velocity-adaptive gain (slow = fine, fast = coarse). Spans all monitors with no seam logic; fist to clutch/reposition.

**Simulated layouts:** Laptop + Ultrawide (asymmetric, vertically offset — the hard case), Dual 27″, and Triple. Displays live in a virtual "world" coordinate space that stands in for macOS's global display coordinates; the mapping math is identical to what Phase 2 will use against real `NSScreen` frames.

**What to report back:** which model feels right (or which blend), and tuned values for edge-dwell time and relative gain. That decision drives the Phase 2 mapping implementation.

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
