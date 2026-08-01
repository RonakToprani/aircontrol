# AirControl — Phase 2 Implementation Plan (native macOS app)

**Goal:** a full-fledged, local-only macOS menu-bar app. Click the menu-bar icon → toggle AirControl on. Pinch in the air to grab and drag real windows; 4-finger swipe to switch Spaces. Multi-monitor support — **two- and three-display setups alike** — must feel *effortless*: the whole desktop reachable from one comfortable hand range, no long arm travel, no getting stranded on the wrong screen. Nothing in the mapping layer may assume exactly two displays or a purely horizontal arrangement.

**Non-goals (v1):** window resizing (planned for **v2** as a two-handed gesture — second hand joins to resize), custom gesture training, multi-user profiles, iOS companion, App Store distribution, any network access. Note for v1 architecture: Vision's `maximumHandCount` stays 1 for now, but keep `GestureEngine` per-hand so a second hand is additive later, not a rewrite.

---

## 1. What Phases 1 and 1.5 actually taught us

**Phase 1 (validated — keep all of it):**
- Index-**fingertip** pointer (landmark 8), with the drag driven by the stable index-**MCP knuckle** (landmark 5) so windows don't lurch when the finger curls to pinch.
- **Render-rate easing**: cursor + dragged window eased toward the latest detection every render frame (60fps), decoupled from the slower camera/detection rate. This is the single biggest "feel" win.
- Pinch normalized by hand size, with signal smoothing + release hysteresis.
- Displacement-over-a-time-window swipe detection (robust to frame drops), one gesture only.
- Live tunables + live diagnostics (FPS, pinch distance readouts, swipe progress bar). Tuning by feel only works when you can *see why* something isn't triggering.
- Tuned constants (§7) that define the target feel.

**Phase 1.5 (inconclusive — verdict does not count against the mapping models):** a code review found the rig broken in ways that guaranteed it would feel bad regardless of which mapping model is right:

1. **The fist clutch could not work.** A real fist puts the thumb tip on the index tip, which reads as a *pinch* — so "clutch" grabbed and dragged whatever was under the cursor. The clutch was the chosen model's core recovery mechanism, and it was unavailable.
2. **Edge-dwell hand-off cascaded.** 260 ms dwell, no post-cross lockout, no hysteresis, trigger zone overlapping the region you use for normal pointing, evaluated at ~7 detection FPS (≈2 samples). Constant accidental display jumps.
3. **After a hand-off you were stranded** — the re-anchor deliberately spent the entire hand range, the "clutch now" hint was never rendered, and the only escape was the broken clutch. The pointer wasn't even clamped, so it could walk into inter-display gaps and drop windows there.
4. **The knuckle drag-driver was dropped**, so every pinch lurched the window — amplified by display width.
5. **Simulator-scale artifacts**: monitors drawn at ~27% scale with a full-size cursor, 2.3× pointer-speed change across the seam, square hand space stretched onto ultra-wide targets (different anisotropy per mode).
6. **~7 detection FPS** (MediaPipe WASM) under everything, which Phase 1's own tuning guide calls the #1 cause of bad feel.
7. **The diagnostics were removed** (no pinch readouts, no swipe progress bar, skeleton reduced to a thumbnail), so none of this was visible while testing.

**Implications for Phase 2:**
- Native Vision on Apple silicon should run hand pose at ~30fps — the FPS ceiling that capped both prototypes largely disappears. Measure this first (M0) before trusting any feel judgment.
- The mapping-model decision is **still open**. Build the mapping layer pluggable and decide in a short bake-off on the real dual-monitor setup (M2), with the rig's defects designed out.
- **Drop the fist clutch from v1 entirely.** It conflicts with pinch by construction, and the designs below remove the need for it.

---

## 2. Product definition

**App shape:** menu-bar-only app (`LSUIElement`, no Dock icon). SwiftUI `MenuBarExtra` dropdown:

- **Enable AirControl** — master toggle (icon shows state: outlined hand = off, filled = on)
- **Calibrate hand range…** — re-runnable pinch-corner calibration (§5.4)
- **Show tuning HUD** — the live slider/readout panel, ported from Phase 1
- **Settings…** — persisted config window
- **Start at login** (SMAppService)
- **Quit**

**Gesture set (deliberately minimal, per Phase 1 decisions):**

| Gesture | Action |
|---|---|
| Open hand, move | Move the AirControl pointer (overlay cursor, not the OS cursor) |
| Pinch (thumb–index) | Grab the window under the pointer; move hand to drag; release to drop |
| 4-finger horizontal swipe | Switch Space left/right |

Multi-monitor reach must require **no additional gesture** in the primary design (§5.2).

**Engagement model:** tracking runs only while enabled. Hand lost > ~300 ms → pointer fades out and *all* gesture state resets (pinch smoothing, swipe history, any relative-mode anchor — Phase 1.5 leaked state across tracking loss; codify the reset list). Hand reacquired → pointer fades in where the mapping says it is. Any active drag is committed (window stays where it was) — never snaps back.

**Own overlay pointer, not the real cursor** (considered and rejected: driving the real cursor + synthetic mouse-drags on title bars would fight simultaneous trackpad use, require title-bar hits, and turn tracking jitter into real clicks). The overlay pointer + Accessibility API moves windows without focusing or raising them and can grab a window anywhere in its frame.

---

## 3. Architecture

```
AVCaptureSession (720p, 30fps, dedicated queue)
        │  CMSampleBuffer
        ▼
Vision  VNDetectHumanHandPoseRequest  (maximumHandCount = 1)
        │  VNHumanHandPoseObservation → LandmarkFrame (adapter)
        ▼
GestureEngine  (pure Swift port of Phase 1 logic — pinch w/ hysteresis,
        │       finger-extension count, displacement-window swipe)
        ▼
MappingEngine  (protocol PointerMapping — pluggable models, §5)
        │  target point in global display coords + gesture events
        ▼
   ┌────┴─────────┬───────────────────┐
   ▼              ▼                   ▼
OverlayRenderer  WindowMover        SpaceSwitcher
(per-screen      (AXUIElement       (CGEvent ⌃←/⌃→)
 click-through   position writes,
 NSWindow,       ghost outline)
 60fps easing)
```

**Module notes:**

- **LandmarkAdapter** — Vision's `VNHumanHandPoseObservation` provides all 21 joints (wrist, per-finger MCP/PIP/DIP/tip); map to the same named points Phase 1 used (`indexTip`, `indexMCP`, `thumbTip`, …) with per-joint confidence gating (drop joints < ~0.3 confidence; drop the frame if wrist/index are unreliable). Vision's coordinates are normalized with origin bottom-left and **not mirrored** — the adapter owns mirroring and axis flips so `GestureEngine` receives exactly Phase 1's coordinate conventions and the ported logic transfers untouched.
- **GestureEngine** — a direct port, kept pure (no AppKit imports) and unit-testable by replaying recorded landmark sequences. Port the *fixed* Phase 1 behaviors: pinch distance normalized by hand size, pinch hysteresis, knuckle-driven drag, displacement-window swipe with cooldown.
- **OverlayRenderer** — one borderless `NSWindow` per screen: `level = .screenSaver`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .stationary]`, transparent, CALayer-drawn cursor (idle ring → hover highlight → pinch dot, as in Phase 1). A display-link-driven render loop does the **per-frame easing toward the detection target** — the Phase 1 smoothness architecture, verbatim. Also draws: window-about-to-grab highlight, ghost outline during drag, swipe progress bar, and (if per-display mapping wins the bake-off) the active-display / reach indicator.
- **WindowMover** — window under pointer via `CGWindowListCopyWindowInfo` (on-screen, layer 0, skipping own overlays); resolve to an `AXUIElement` by matching the owning PID's `kAXWindowsAttribute` entries by frame (private `_AXUIElementGetWindow` only as a guarded fallback). On pinch: capture window + grab offset. During drag: write `kAXPositionAttribute`.
  **Known gotcha:** AX position writes are synchronous and slow for some apps (Electron/Chrome can take tens of ms). Mitigation: the *ghost outline* on the overlay is what tracks the hand at 60fps; AX writes are throttled to what the target app can absorb (adaptive — measure write latency, back off), with a guaranteed final write on release. Native apps will track live; slow apps degrade to outline-follows-hand + window-commits-on-drop, never to a laggy pointer.
- **SpaceSwitcher** — post ⌃← / ⌃→ via `CGEvent` (requires the default Mission Control shortcuts to be enabled — detect and surface in onboarding if remapped). With "Displays have separate Spaces" on, the switch targets the active display; if that proves wrong in testing, warp the real cursor (`CGWarpMouseCursorPosition`) to the AirControl pointer's display before posting, then restore.
- **Config** — one `Codable` struct, persisted via `UserDefaults`, seeded from the Phase 1 tuned constants (§7). Every constant bound to a HUD slider. Nothing hardcoded — this is a standing rule.

**Permissions & packaging:** Camera (TCC) + Accessibility (`AXIsProcessTrustedWithOptions`) — onboarding flow checks both and deep-links to System Settings. **Not sandboxed** (AX requires it; personal tool, no App Store). Sign with a stable Developer ID / development certificate from day one — ad-hoc signing changes the code signature every build and macOS revokes the Accessibility grant each time, which makes iteration miserable. Target macOS 14+.

---

## 4. Feel spec (the non-negotiables)

1. **Two-rate architecture**: detection at camera rate (~30fps native), display eased at render rate (60–120fps via display link). Never render raw detections.
2. **1€ filter for pointer smoothing** (upgrade over Phase 1's fixed EMA): jitter-adaptive — heavy smoothing when the hand is still (rock-steady pointing), light smoothing when it moves fast (no lag). This directly serves "small hand range covers big desktop" — it recovers the precision that a wide mapping spends. Seed its `minCutoff`/`beta` so slow-speed behavior matches posAlpha 0.35; both are HUD sliders. Keep plain EMA as a HUD-selectable fallback for A/B feel comparison.
3. **Fingertip pointer, knuckle drag** — cursor on `indexTip`, drag displacement from `indexMCP`. Never regress this again.
4. **Sticky window targeting**: the window-under-pointer highlight has spatial hysteresis (once highlighted, a window stays targeted until the pointer clearly exits), so jitter never flicks the target at grab time.
5. **All diagnostics ported**: Detect FPS, pinch dist raw/smooth, fingers-extended count, swipe progress bar, active mapping state. The HUD is a first-class feature, not scaffolding.
6. **Defined state-reset on tracking loss** (§2) and on display-configuration change (`didChangeScreenParametersNotification` → rebuild overlays, re-derive mapping topology, drop any in-flight drag safely).

---

## 5. Multi-monitor mapping (the heart of the plan)

### 5.1 Principles

- **Precision demand is low; reach comfort is everything.** AirControl points at *windows* (hundreds of px), not buttons. This changes the trade-off that motivated per-display mapping: spreading the hand range across two displays halves precision, but halved precision may still be far more than window-grabbing needs — while eliminating seams, modes, and extra gestures entirely. Phase 1.5 could not test this fairly (7fps, tiny simulated monitors, gaps included in the mapping).
- **Gap-collapsed union**: build the mapping target from real `NSScreen` frames with inter-display gaps and non-covered regions collapsed out, so no hand range is ever spent on dead space and the pointer can never enter a gap. Pointer always clamped to the union; a point that lands in dead space snaps to the nearest display edge.
- **Aspect handled by calibration, not by forced isotropy**: the calibrated comfortable hand rect is naturally wide (horizontal arm sweep is easy, vertical is not), which matches a wide desktop. Per-axis linear mapping from the calibrated rect; the HUD shows the effective X and Y gain so mismatch is visible instead of mysterious.
- **Every crossing/anchor mechanism is gated on the *pointer* vs display geometry** — never on raw hand-space position (Phase 1.5's dwell zone overlapped the pointing range; that class of bug is ruled out structurally).

> **Decision (Ronak, 2026-08-01): the per-display + edge-crossing model (§5.3) is the chosen design.** Crossing monitors works like a mouse: push the pointer against the shared edge and it slides onto the neighbor — no gesture, no big arm travel, because the full hand range always maps to just the current display. The 4-finger swipe means exactly what it means on the trackpad — switch Spaces — and is never used for display switching. Model A below is kept only as a HUD-switchable comparison during M2 tuning; Model C stays reserve.

### 5.2 Model A — continuous absolute across the whole desktop (comparison baseline)

The calibrated hand range maps to the entire gap-collapsed union. Hand position *is* desktop position: glance at the far monitor, point there, you're there. **Zero seams, zero modes, zero new gestures, zero stranding** — and minimal hand travel by construction, which is the stated dual-monitor requirement.

Precision compensation: 1€ filter (§4.2) + sticky targeting (§4.4). Optional refinement if fine positioning still feels coarse: **precision-on-pinch** — while pinching (dragging), scale hand deltas down by a tunable factor (e.g. 0.6×) around the grab point; releasing re-syncs absolutely.

**Scaling caveat:** Model A's effective jitter and coarseness grow linearly with desktop width. At two displays it's probably fine for window-sized targets; at **three** displays the hand range is spread ~3× and precision-on-pinch likely graduates from "optional" to "on by default." The M2 bake-off tests this explicitly rather than assuming — if Model A only survives two displays, Model B (which is display-count-invariant) wins for wider setups, or the model becomes a per-arrangement setting.

### 5.3 Model B — per-display absolute + corrected crossing (CHOSEN)

Full hand range maps to the **active display only** (maximum precision). Crossing to a neighbor, with every Phase 1.5 defect fixed:

- **Trigger:** the *pointer* reaches a shared edge **and** the hand keeps pushing — commit on overshoot travel past the edge (~6–10% of hand range, tunable) *or* ≥350 ms sustained pressure. Pressure meter rendered at the seam.
- **Hysteresis + lockout:** after a cross, no *unintentional* re-cross — the pointer must move a minimum distance away from the seam *and* ~500 ms must elapse before edge pressure re-arms. Cascading-by-accident is impossible by construction.
- **Chained crossing (3+ displays):** the lockout must not make a two-seam traversal (display 1 → 3) sluggish. If the hand is still *actively pushing* when the pointer lands on the new display's entry edge, pressure keeps accumulating and the next seam commits without the full lockout — deliberate sustained push glides across the whole desktop; only stopping re-arms the guard. Tunable, tested on the triple layout in M2.
- **Any seam orientation:** neighbor topology is derived from real `NSScreen` frames as shared-edge segments — horizontal, vertical, offset, and mixed-size arrangements all produce the same pointer-vs-edge crossing mechanics. (The Phase 1.5 rig only handled horizontal neighbors; this is a required fix, not an inheritance.)
- **Entry-edge anchor with recentering decay** (this replaces the clutch): on commit, re-anchor so the current hand position = the entry edge (short eased tween across the physical seam, y-aligned). Then, whenever the hand is *moving*, the anchor gradually slews back toward the canonical full-range mapping (rate ∝ hand speed, so it's imperceptible — the same trick VR pointers use for drift correction). Reach is recovered automatically within a second of normal movement. **No fist, no clutch gesture, nothing to misdetect.**
- **Always visible:** a subtle active-display indicator (edge glow on the overlay) so the current anchor state is never a mystery.
- 4-finger swipe stays reserved for Spaces (no overloading).

### 5.4 Calibration

Pinch at comfortable top-left → pinch at comfortable bottom-right (with a countdown + live preview rect). Defines the hand rect used by both models. Re-runnable from the menu bar; stored per camera. Falls back to the margin-based default (Phase 1's `margin 0.15` behavior) until run.

### 5.5 M2 — tuning & validation of the chosen model

Model B is the design; M2 is about making the edge-crossing *feel* right on **real hardware** at native FPS, pointer-only (no window dragging yet). Models A/C stay behind the `PointerMapping` protocol as live-switchable comparisons (keys `1`/`2`/`3`) so "is B actually better?" can be sanity-checked in one keypress, but B ships unless it fails these on the real setup — including a three-display session even if temporary (borrowed monitor / TV over HDMI counts):

- Reach the far corners of **every** display from one seated, elbow-down hand position, without re-gripping or strain.
- Land the pointer on a specific ~400px window on any display within ~1s, ten times in a row (crossing included).
- Hold the pointer inside a 100px circle for 3s (jitter test).
- Traverse leftmost display → rightmost display in under ~1.5s (chained crossing).
- No unintended display crossing during 2 minutes of normal pointing.
- Crossing feels like a mouse hitting the seam — deliberate push crosses immediately-ish; casual pointing near the edge never does.

Tunables to dial in: crossing overshoot / dwell / lockout, anchor-recentering decay rate, seam tween duration.

Model C (pure relative/trackpad + velocity gain) stays in reserve on the protocol, only implemented if both A and B fail — with the Phase 1.5 lessons applied (speed computed on filtered positions, gain capped, delta reset on tracking loss).

---

## 6. Milestones

Each milestone ends in something you can *feel* and tune; the plan front-loads the two real risks (native tracking quality, mapping model).

- **M0 — Tracking spike (½ day):** Xcode scaffold, menu-bar toggle, camera permission, capture → Vision → landmark log + bare dot overlay. **Measure detect FPS and landmark stability on the actual MacBook.** Go/no-go data for everything downstream; if Vision underperforms expectations, know it *now*.
- **M1 — Phase 1 parity on one display:** GestureEngine port, overlay cursor with render-rate easing, 1€ filter, tuning HUD with all diagnostics, calibration. Acceptance: matches or beats the Phase 1 web feel on the built-in display (pointer + pinch state + swipe detection against mock highlights, no real windows yet).
- **M2 — Edge-crossing feel:** implement Model B (per-display + mouse-like edge crossing) on real displays (two-display daily setup, plus a three-display session per §5.5); run the acceptance tests; tune crossing/decay constants. Models A/C stay one keypress away as sanity checks. *This validation is what Phase 1.5 failed to deliver.*
- **M3 — Real window dragging:** WindowMover (AX), knuckle-driven drag, ghost outline + adaptive AX write throttling, sticky targeting, drop-commit semantics. Acceptance: drag Finder, Safari, and one Electron app smoothly between both displays.
- **M4 — Space switching:** swipe → `CGEvent` ⌃←/⌃→, cooldown honored, separate-Spaces-per-display behavior verified.
- **M5 — Productization:** onboarding (camera + Accessibility walkthrough, Mission Control shortcut check), settings persistence, start-at-login, sleep/lid/camera-contention handling, display hot-plug handling, menu-bar state icon, idle CPU discipline (camera fully off when disabled).

---

## 7. Seed constants (from Phase 1 tuning)

| Constant | Value | Notes |
|---|---|---|
| Position smoothing (posAlpha) | 0.35 | Seeds the 1€ filter's slow-speed behavior; EMA fallback keeps it directly |
| Pinch signal smoothing (pinchAlpha) | 0.50 | Slider was missing in 1.5 — must exist |
| Pinch threshold | 0.42 | Re-verify against Vision's landmark scale via the pinch-dist readouts |
| Pinch release hysteresis | 0.12 | |
| Edge margin (pre-calibration default) | 0.15 | |
| Swipe travel distance | 0.16 | |
| Swipe time window | 500 ms | Slider was missing in 1.5 — must exist |
| Swipe cooldown | 1650 ms | |
| Swipe min fingers | 3 | |
| Finger "extended" threshold | 1.08 | The fist-vs-swipe tension this created is gone with the clutch removed |
| Mirror camera | on | Owned by LandmarkAdapter |
| New: 1€ minCutoff / beta | tune in M1 | HUD sliders |
| New: crossing overshoot / dwell / lockout (Model B) | 8% / 350 ms / 500 ms | HUD sliders, tune in M2 |

Vision's landmark geometry won't be numerically identical to MediaPipe's — expect thresholds (pinch especially) to shift. The readouts exist precisely so re-tuning takes minutes.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Vision hand-pose FPS or stability worse than expected | M0 spike measures before any architecture is built on it; lighting guidance in onboarding; 720p capture (pose quality saturates, FPS wins) |
| Built-in camera caps at 30fps | Acceptable — render-rate easing was designed for exactly this; Phase 1 felt good at lower |
| AX writes slow/refused for some apps (Electron, some cross-platform UI) | Ghost-outline decoupling + adaptive throttle + commit-on-drop (§3); per-app measured latency in HUD |
| Space-switch shortcut remapped/disabled by user | Detect at onboarding; instruct; no private CGS APIs in v1 |
| Camera FOV/pose varies by seating position | Re-runnable calibration is a menu-bar item, not buried |
| Accessibility grant reset during development | Stable signing certificate from day one (§3) |
| False gesture triggers while hand incidentally in frame | Master toggle is the primary guard; confidence gating + hand-lost reset; if still noisy, add an explicit open-palm-hold engage in M5 (only if needed — keep the gesture set minimal) |

---

*Phase 1 prototypes: `phase1/index.html` (feel — validated), `phase1.5/index.html` (mapping rig — superseded by the M2 bake-off; kept for reference).*
