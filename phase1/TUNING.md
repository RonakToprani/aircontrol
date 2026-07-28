# Phase 1 — Tuning Guide

Every value below is a **live slider** in the on-page panel (top-right). Nothing is hardcoded — tune by feel while gesturing, then copy the numbers you land on into the Phase 2 Swift app. Defaults live in the `DEFAULTS` block at the top of the `<script>` in [`index.html`](index.html).

The fastest way to tune: watch the **live readouts** at the bottom of the panel while you move — `Gesture`, `Pinch dist (raw / smooth)`, `Fingers extended`, `Detect FPS`. They tell you *why* something isn't triggering.

> **Start here:** if `Detect FPS` is below ~15, fix that before touching any slider (see [Detect FPS is low](#detect-fps-is-low--15--fix-this-first)). Low FPS is the #1 cause of laggy dragging and flaky swipes.

**Pointer position:** the cursor tracks your **index fingertip**. When you pinch, the *drag* is driven by the index knuckle (which barely moves as the finger curls), so a grabbed window doesn't jump at the moment you pinch — the cursor stays on the fingertip, the window stays put.

---

## How the pipeline works (so the knobs make sense)

```
camera frame ──► MediaPipe (21 landmarks) ──► gesture logic ──► TARGET position
   ~15–30 fps                                                        │
                                                                     ▼
render loop (60 fps) ──► ease displayed cursor/window toward TARGET ──► screen
```

Two separate rates matter:

- **Detection rate** (`Detect FPS`, ~15–30) — how often the camera + model produce new hand data. You don't control it directly; it depends on lighting, CPU, and `modelComplexity`.
- **Render rate** (~60fps) — how often the screen redraws. The cursor and any dragged window are **eased toward the latest detection target every render frame**, which is what makes motion glide instead of stepping at the (slower) detection rate.

This is why smoothness and accuracy are mostly about the **smoothing** and **threshold** knobs, not the camera.

---

## Smoothness — dragging feels laggy, jittery, or "steppy"

### `Position smoothing (posAlpha)` — the main one
Per-render-frame easing toward the hand's latest position. Frame-rate-independent, so the feel is consistent even when `Detect FPS` dips.

| Symptom | Fix |
|---|---|
| Cursor/window **jitters** or twitches while holding still | **Lower** posAlpha (e.g. 0.35 → 0.22). More smoothing. |
| Cursor **lags behind** your hand / feels floaty and disconnected | **Raise** posAlpha (e.g. 0.35 → 0.5). Tighter follow, less latency. |
| Dragging looks like it **steps/stutters** in chunks | You're likely on old behavior — this build eases at 60fps; if it still steps, raise `Detect FPS` (see below) and keep posAlpha ≥ 0.3. |

**The trade-off is always smoothness vs. latency.** For dragging windows, a touch more smoothing (0.25–0.35) feels good. For precise pointing, tighter (0.4–0.5). Pick for the task you do most.

### `Detect FPS` is low (< ~15) — fix this FIRST
Not a slider — it's a readout, and it's the **most important number on the panel**. If it's low (e.g. 7), everything feels laggy and swipes are unreliable no matter how you set the smoothing, because the model is only producing a hand position 7×/second. Raise it before tuning anything else:

- **Leave `Accurate model` OFF** (the default). Off = MediaPipe's *lite* model, which roughly doubles FPS for a small accuracy cost. Only turn it on if your FPS is already high (20+) and you want steadier landmarks. You can flip it live and watch `Detect FPS` react.
- Improve **lighting** on your hand — the single biggest real-world factor.
- Keep the hand **fully in frame** and not too far from the camera.
- Close other heavy apps / unplug from an external 4K display if the machine is thermally throttling.

Target ≥ 15 FPS for usable feel, ≥ 25 for great feel. The render-easing keeps motion smooth *between* detections, but it can't invent hand data that isn't there — so FPS sets the ceiling.

---

## Pinch — grabbing/dropping windows is unreliable

### `Pinch threshold (pinchThresh)`
The normalized thumb-tip↔index-tip distance below which a pinch engages. **Normalized by hand size**, so it's the same near or far from the camera. Watch `Pinch dist (smooth)` while you pinch and un-pinch to read your actual numbers.

| Symptom | Fix |
|---|---|
| Pinch **won't register** / you have to squeeze very tight | **Raise** pinchThresh (e.g. 0.42 → 0.55). Watch `Pinch dist (smooth)` — set the threshold a bit **above** the value you see when pinched. |
| Windows grab **by accident** when you didn't pinch | **Lower** pinchThresh (e.g. 0.42 → 0.32). Set it **below** your relaxed-hand `Pinch dist`. |

**Method:** pinch and read `Pinch dist (smooth)` (call it *P_closed*); relax and read it again (*P_open*). Set `pinchThresh` roughly halfway between, closer to *P_closed* if you want it easy to grab.

### `Pinch release hysteresis (pinchHyst)`
Extra gap the distance must re-open past before a pinch *releases*. Stops flicker at the boundary — i.e., a window that keeps grabbing/dropping rapidly.

| Symptom | Fix |
|---|---|
| Window **flickers** between grabbed/dropped while dragging | **Raise** pinchHyst (e.g. 0.12 → 0.20). |
| Drop feels **sticky** / slow to let go | **Lower** pinchHyst (e.g. 0.12 → 0.06). |

### `Pinch signal smoothing (pinchAlpha)`
Smooths the pinch *distance* before the threshold test. Higher = more responsive pinch, lower = steadier but slightly delayed. If pinch state feels noisy, **lower** it (0.5 → 0.35); if it feels laggy to engage, **raise** it.

---

## Pointing accuracy — cursor doesn't land where you aim

### `Edge margin (margin)`
The fraction of each axis treated as a dead-zone at the frame edges. The usable hand range `[margin, 1-margin]` is stretched to fill the whole screen, so you don't have to reach the literal edge of the camera view.

| Symptom | Fix |
|---|---|
| Can't reach screen **corners/edges** without your hand leaving frame | **Raise** margin (e.g. 0.15 → 0.25). Smaller hand range covers the whole screen — easier reach, but coarser (a small hand move covers more screen). |
| Cursor is **too twitchy** / small hand moves fly across the screen | **Lower** margin (e.g. 0.15 → 0.08). Larger hand range → finer control, but you must reach further. |

`margin` is the accuracy-vs-reach trade. If you also want finer control, pair a lower margin with a lower posAlpha.

### `Mirror camera`
On by default so moving your hand right moves the cursor right. Turn off if the mapping feels reversed.

---

## Four-finger swipe — switching windows/Spaces misses or mis-fires

Detection is **displacement over a time window**: four fingers must travel `swipeDist` within `swipeMaxTime` ms. This is robust to frame-rate and brief tracking dropouts. The green **progress bar above the cursor** fills as you sweep — if it barely moves, the *palm isn't being registered*, not that the swipe is too strict (check `Fingers / thumb` reads `4/4`).

| Symptom | Fix |
|---|---|
| Swipe **rarely triggers** even on a clear sweep | **Lower** `Swipe travel distance` (0.16 → 0.11) **or** raise `Swipe time window` (500 → 700ms) to allow a slower sweep. |
| Palm **not detected** (progress bar/finger count stays low) | Lower `Swipe min fingers` to **3**, or lower `Finger "extended" threshold` (1.45 → 1.30) so fingers count as extended more easily. Improve lighting. |
| Swipe fires **by accident** while just moving your hand | **Raise** `Swipe travel distance` (0.16 → 0.22) and/or **lower** `Swipe time window` (500 → 380ms) so only a fast, deliberate sweep counts. |
| One sweep switches **multiple** windows | **Raise** `Swipe cooldown` (700 → 1000ms). |
| Nothing happens right after a successful swipe | That's the cooldown working — wait it out, or lower it. |

### The individual swipe knobs
- **`Swipe travel distance`** — how far (as a fraction of frame width) the hand must move. Lower = more sensitive.
- **`Swipe time window`** — the sweep must complete within this many ms. Longer = allows slower sweeps but risks catching drift; shorter = demands a snappy sweep.
- **`Swipe cooldown`** — lockout after a swipe so one gesture fires once. Raise if you get double-switches.
- **`Swipe min fingers`** — 3 or 4. Set **3** if a full 4-finger spread is hard to hold; **4** if you get accidental swipes.
- **`Finger "extended" threshold`** — how straight a finger must be to count as extended. Lower = fingers count more easily (helps detection), higher = stricter.

---

## Recommended starting recipes

**Priority: smooth, forgiving window dragging** (what we're tuning for now)
- posAlpha **0.30**, pinchThresh set from your readings, pinchHyst **0.18**, margin **0.18**.

**Priority: precise pointing**
- posAlpha **0.45**, margin **0.08**, pinchHyst **0.10**.

**Priority: reliable swipes in poor lighting**
- Swipe min fingers **3**, Finger extended threshold **1.30**, Swipe travel distance **0.12**, Swipe time window **650ms**.

When it feels right, note the numbers — they carry straight into Phase 2.
