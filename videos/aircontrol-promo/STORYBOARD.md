---
format: 1920x1080
duration: 26s
message: "Your Mac, controlled by a wave of your hand."
arc: Demo Loop — hook (the magic move) → promise → gesture cycle ×5 → trust → brand
audience: Mac users who love new tech — indie devs, designers, the X / TikTok / Product Hunt crowd
mode: autonomous
music: Minimal Techno 01 (Mixkit, Alejandro Magaña) — assets/bgm-minimal-techno-01.mp3, ~129 BPM tech house, cut to 26.3s; see ATTRIBUTION.md
---

## Video direction

- **Palette (frame.md, dark register only):** ground `ink-black` #0A0E14 (with `ink-black-alt` #10151D for raised surfaces such as the mock windows), text `cream` #F2F5F9, secondary text `cream-muted`, hairlines `border-dark`, the ONE accent `fire-orange` = teal #33BFD4 — it is the pointer ring, the kicker labels, the glow, the accent rule. Dictation is the single exception: the ring turns a warm orange (#F0A050) while listening, because that is what the real app does. No gradients other than a very soft teal radial glow behind a hero. No purple/blue "AI" washes.
- **Type (frame.md ramp, by role):** `display` / `h1` for the big lowercase statements (Inter 800, tight, lowercase — the Broadside primitive), `label` (IBM Plex Mono, uppercase, 0.14em) for the gesture names and kickers, `lead` for the one sentence that explains a gesture. Lowercase statements are the house voice — "no mouse." not "No Mouse."
- **The two recurring props (source-traceable, never generic):** (1) the **pointer ring** — the app's HUD cursor: a thin teal circle with a soft glow, that **shrinks and brightens when pinching** (teal), **turns indigo when scroll-grabbing**, **turns orange when dictating**; (2) the **hand constellation** — the 21-landmark hand (wrist, four thumb joints, four joints on each finger) drawn as dots joined by hairlines, exactly like the landing page's constellation and the app icon. The hand changes POSE per gesture (open palm → thumb+index pinched → fist → fist with thumb out sideways → pinch held still). Mock windows are flat macOS-style cards: `ink-black-alt` surface, 1px `border-dark`, three traffic-light dots, a title, faint content lines.
- **Motion grammar:** long-tail settles (`power3` / expo on fast arrivals), never bouncy. The whole film is **cut on the music's pulse**: statements land on beats, gesture frames are each ~2.6–3.2s (≈ 4–5 beats at 100 BPM). Wordless — reveals are paced to the ON-SCREEN TEXT cues, which play the role the voiceover usually plays: nothing enters before its cue; the back half of every frame still has something arriving. Seams inside a frame are velocity-matched cuts.
- **Rhythm / held frames:** Frame 2 (promise) and Frame 8 (trust) are the deliberate still reads — type lands, then holds. Frame 9 holds on the lockup for its last ~1.2s. Every other frame has the hand DOING something until the cut.
- **Negative list:** no price, no "free", no "beta", no pricing words of any kind; no real cursor arrows, no browser chrome, no nav bars; no stock bokeh or particle fields; no slideshow (dump-then-freeze) and no screensaver (everything drifting). No infinite loops, no randomness. The URL appears exactly once, small, in the final frame; the product NAME is always bigger than the URL. The camera does not drift in the back half of any frame.
- **Caption band:** captions are not used, but all type still sits in the top ~83% of the canvas.
- **9:16 note:** every frame is composed with a centered hero and a single column of type so a portrait cut (1080x1920) can stack the hand ABOVE the window instead of beside it; workers keep the hand and the window as two separate wrappers for that reason.

## Frame 1 — The move

- scene: a window sits alone on a dark desktop; the teal pointer ring glides in, pinches, and THROWS the window across the screen — then "no mouse." / "no trackpad." slam in
- voiceover: ""
- duration: 3.4s
- transition_in: cut
- status: animated
- src: compositions/frames/01-the-move.html
- type: hook
- persuasion: Visual spectacle — show the impossible thing before saying a word
- beat: curiosity → awe
- blueprint: cursor-ui-demo (Adapt)
- focal: hand-constellation + pointer ring over a mock window (hand-authored props; no captured asset is the hero)
- roles: mock window = supporting · pointer ring = cutout · hand constellation = cutout (small, lower-left, the "who is doing this") · dark ground with soft teal glow = background
- asset_candidates: assets/screenshots/scroll-000.png — the landing page hero, reference only for the window/ring look (not shown on screen)
- sfx: whoosh-soft, impact-soft
- handoff_out: none — hard cut

narrativeRole: The hook. The first second must stop the scroll: a window moves with nothing touching it. Only after the move do the words explain the absence of a mouse.
keyMessage: Something just moved a window — and it wasn't a mouse.

Adapt: keep cursor-ui-demo's signature (a visible custom pointer drives a reconstructed UI and the screen changes state) but the pointer is the app's teal ring driven by a hand, not an arrow; the state change is the window's position.
Scene 1 (0.0–0.5s): the ground and ONE mock window ("Notes", left-of-center, ~34% of the frame) are already there, still; a faint teal radial glow sits behind it (`ambient-glow-bloom`). Nothing else. Rule-of-thirds, 3 depth layers (glow / window / ring).
Scene 2 (0.5–1.3s): the pointer ring enters from the lower-right on a fast decelerating arc and settles over the window's title bar — a fast decelerating arc, smooth; the small hand constellation (open palm) fades up lower-left, mirroring the ring's path at a fraction of the amplitude — the ring is the hand.
Scene 3 (1.3–1.5s): PINCH — thumb and index dots of the constellation close together; the ring shrinks to ~65% and brightens; the window gets a 1px teal outline (the app's ghost) and lifts (shadow deepens). `press-release-spring` on the ring, smooth, no bounce.
Scene 4 (1.5–2.3s): the window is THROWN: ring + window travel together on one long expo arc from left-of-center to right-of-center with a brief directional blur on the window during the fastest 200ms, settle; ring releases (back to full size), outline fades. The hand constellation's pinch opens again.
Scene 5 (2.3–3.4s): on the beat, `h1` "no mouse." slams in upper-left (`kinetic-beat-slam`), then 0.5s later "no trackpad." beneath it — hard entrances, long-tail settle, no overshoot. Hold the read for the last 0.4s; the ring idles with the faintest positional jitter only.

## Frame 2 — The promise

- scene: full-frame statement — "control your mac" / "with a wave of your hand." — lowercase display type, word by word
- voiceover: ""
- duration: 2.6s
- transition_in: zoom-through
- status: animated
- src: compositions/frames/02-promise.html
- type: product_intro
- persuasion: Future pacing — name the new normal in one line
- beat: clarity + aspiration
- blueprint: kinetic-type-beats (Reproduce)
- focal: the statement itself (typography only)
- roles: statement = cutout · ground = background
- asset_candidates:
- sfx: riser-short

narrativeRole: The value claim, landed by beat 2 (story spine rule 2). It is the message verbatim, and it reads as a promise rather than a feature.
keyMessage: Your Mac, controlled by a wave of your hand.

Reproduce: the words ARE the motion; one statement builds across beats onto a payoff.
Scene 1 (0.0–1.0s): bare ground. "control your mac" assembles via `per-word staggered reveal` (`dynamic-content-sequencing`), `display` role, centered, ~60% width, each word a beat, long-tail settle.
Scene 2 (1.0–1.9s): the second line "with a wave of your hand." arrives beneath on the next beat, same move; "hand" lands last and lights up teal with a single soft glow hit (one attack-decay envelope, then rests).
Scene 3 (1.9–2.6s): held read. Still. A thin 36×2 teal accent rule (`rule` component) scales in from the left under the lines as the only movement.

## Frame 3 — Point

- scene: the open-hand constellation at left; at right the pointer ring sweeps across a desktop with two windows, hovering each — kicker "POINT", line "an open hand moves the cursor."
- voiceover: ""
- duration: 2.6s
- transition_in: zoom-through
- status: animated
- src: compositions/frames/03-point.html
- type: feature_showcase
- persuasion: Show-don't-tell proof — the gesture and its effect in the same shot
- beat: control
- blueprint: panel-edit-live-sync (Adapt)
- focal: hand constellation (open palm) coupled to the pointer ring
- roles: hand constellation = cutout (left column, ~30% width) · desktop with two mock windows = supporting (right 60%) · ring = cutout · kicker + line = supporting
- asset_candidates:
- sfx: tick-soft
- handoff_out: hand constellation at x≈22% / y≈50% of frame, scale 1, opacity 1, still, open-palm pose; pointer ring resting over the right window's title bar at x≈72% / y≈42%, scale 1, opacity 1, still

narrativeRole: First of the five gesture beats — the simplest one, so the viewer learns the grammar of the sequence (hand left, effect right, name on top).
keyMessage: Open hand = cursor.

Adapt: keep panel-edit-live-sync's signature (a control manipulated on one side, the bound surface answering live on the other, camera never loses the couple); the "control" is the hand pose, the surface is the desktop.
Scene 1 (0.0–0.6s): asymmetric 30/70. The hand constellation (open palm) draws itself in at left via `SVG self-draw` (`svg-path-draw`) — hairlines first, then the 21 dots pop in with a smooth long-tail settle (`spring-pop-entrance`). The kicker `label` "POINT" fades up above it in teal.
Scene 2 (0.6–1.9s): the hand drifts right a little and the ring on the desktop mirrors the move at full amplitude — sweeping from the left window to the right window; each window gets the sticky-hover teal ghost outline as the ring crosses it (hover on, hover off). The bound surface answers live.
Scene 3 (1.9–2.6s): the `lead` line "an open hand moves the cursor." reveals under the kicker via `per-word staggered reveal`; ring settles over the right window; hold.

## Frame 4 — Pinch

- scene: the constellation closes thumb+index; the ring shrinks teal, grabs the window and drags it in an arc; kicker "PINCH", line "pinch to click. hold to drag."
- voiceover: ""
- duration: 3.2s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/04-pinch.html
- type: feature_showcase
- persuasion: Show-don't-tell proof
- beat: power
- blueprint: panel-edit-live-sync (Adapt)
- focal: hand constellation (pinch pose) coupled to the ring + the dragged window
- roles: hand constellation = cutout (left ~30%) · desktop with two mock windows = supporting · ring = cutout · kicker + line = supporting
- asset_candidates:
- sfx: click-soft, whoosh-soft
- handoff_in: hand constellation at x≈22% / y≈50%, scale 1, opacity 1, still, open-palm pose; pointer ring over the right window's title bar at x≈72% / y≈42%, scale 1, opacity 1, still
- handoff_out: hand constellation at x≈22% / y≈50%, scale 1, opacity 1, open-palm pose (pinch released); ring at x≈60% / y≈52%, scale 1, opacity 1, still

narrativeRole: The hero gesture (it is the one everyone will try first). Same stage as Frame 3 so the sequence reads as one surface.
keyMessage: Pinch = click; pinch-and-hold = drag anything.

Adapt: same couple as Frame 3; the manipulation is a pose change (open → pinch) and the surface answer is a window being dragged.
Scene 1 (0.0–0.5s): same stage, continuing from the handoff. The kicker `label` swaps "POINT" → "PINCH" by `hard-cut word-swap` (`discrete-text-sequence`).
Scene 2 (0.5–0.9s): the constellation's thumb-tip and index-tip dots travel together and meet (the pinch); the ring shrinks to ~65% and brightens; the right window gets the 1px teal ghost outline and lifts (`press-release-spring`, smooth).
Scene 3 (0.9–2.2s): DRAG — ring and window move together along a smooth S-curve toward the lower-center of the desktop, the hand constellation making the same S at ~1/3 amplitude; a brief directional blur only at the fastest point. Release: fingertips part, ring back to full, outline fades, window settles with a deepening-then-relaxing shadow.
Scene 4 (2.2–3.2s): the `lead` line "pinch to click. hold to drag." reveals under the kicker via `per-word staggered reveal` — two cues, one per sentence. Hold.

## Frame 5 — Fist

- scene: the constellation closes into a fist; the ring turns indigo and a long document inside the window scrolls with momentum; kicker "FIST", line "make a fist to scroll."
- voiceover: ""
- duration: 2.8s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/05-fist.html
- type: feature_showcase
- persuasion: Show-don't-tell proof
- beat: ease
- blueprint: panel-edit-live-sync (Adapt)
- focal: hand constellation (fist pose) coupled to a scrolling document window
- roles: hand constellation = cutout (left ~30%) · one tall mock window with document rows = supporting (right 60%, ~55% of frame height) · ring = cutout · kicker + line = supporting
- asset_candidates:
- sfx: scroll-tick
- handoff_in: hand constellation at x≈22% / y≈50%, scale 1, opacity 1, open-palm pose; ring at x≈60% / y≈52%, scale 1, opacity 1, still

narrativeRole: Third gesture; the one that proves this is daily-usable (scrolling is what people do most).
keyMessage: Fist = scroll, with momentum.

Adapt: the couple holds; the manipulation is a pose change (open → fist, thumb tucked) and the surface answer is a document scrolling.
Scene 1 (0.0–0.5s): kicker swaps "PINCH" → "FIST" (`hard-cut word-swap`). The desktop now shows one tall "Document" window filling the right column (it was the right window, grown — `card morph-anchor` on the window frame, smooth).
Scene 2 (0.5–1.0s): the constellation's finger dots curl down into a fist (each finger chain folds, staggered by finger index); the ring turns INDIGO and shrinks slightly — the scroll grab.
Scene 3 (1.0–2.1s): the hand moves up ~12% of frame height; the document's rows scroll up at ~3× that distance, then COAST with decaying momentum after the hand stops (a long expo tail) — rows are faint lines and a couple of bolder "headings" so the motion reads.
Scene 4 (2.1–2.8s): the `lead` line "make a fist to scroll." reveals (`per-word staggered reveal`); fist opens, ring returns to teal; hold.

## Frame 6 — Thumb

- scene: fist with the thumb out sideways; the WHOLE desktop slides left to the next Space, a second desktop with different windows pushes in; kicker "THUMB", line "point your thumb to switch desktops."
- voiceover: ""
- duration: 2.6s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/06-thumb.html
- type: feature_showcase
- persuasion: Show-don't-tell proof
- beat: delight
- blueprint: panel-edit-live-sync (Adapt)
- focal: registry block `page-slide` (the outgoing/incoming desktop panels) driven by the hand constellation's thumb pose
- roles: hand constellation = cutout (left ~30%) · two desktop panels (current Space with the document window / next Space with two small windows) = supporting · a tiny teal "Space ⟶" flash (the app's own HUD flash) = supporting · kicker + line = supporting
- asset_candidates:
- sfx: whoosh-soft

narrativeRole: Fourth gesture — the biggest visible effect for the smallest hand move; the "wait, what?" beat for the feed.
keyMessage: Thumb sideways = next desktop.

Adapt: the couple holds; manipulation = thumb dot swings out sideways from the fist and holds ~0.3s (the app's hold time); surface answer = the entire right-column desktop panel push-slides to the next Space using `page-slide`.
Scene 1 (0.0–0.5s): kicker swaps "FIST" → "THUMB". The right column is the current desktop panel (document window, small).
Scene 2 (0.5–1.0s): the constellation's thumb chain swings out to point RIGHT and holds; a thin teal hold-meter arc fills around the ring (`stat-bars-and-fills`, ring variant) over ~0.3s.
Scene 3 (1.0–1.7s): the desktop panel push-slides LEFT out of the column as the next Space's panel pushes in from the right (`page-slide`), with the tiny "Space ⟶" `label` flashing once at the top of the column — exactly the app's HUD flash. Smooth expo, no bounce.
Scene 4 (1.7–2.6s): the `lead` line "point your thumb to switch desktops." reveals (`per-word staggered reveal`); thumb tucks back; hold.

## Frame 7 — Speak

- scene: pinch held still over a text field; the ring turns ORANGE and listens; words type themselves into the field: "ship it tonight"; kicker "SPEAK", line "pinch and hold — speak instead of type."
- voiceover: ""
- duration: 2.9s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/07-speak.html
- type: feature_showcase
- persuasion: Feature-to-benefit translation — the keyboard is gone too
- beat: awe
- blueprint: prompt-type-submit-generate (Adapt)
- focal: a mock message-compose window with one empty text field, the orange ring held over it, text typing in
- roles: hand constellation (pinch held still) = cutout (left ~30%) · compose window with text field = supporting · ring (orange) = cutout · kicker + line = supporting
- asset_candidates:
- sfx: tick-soft, type-soft

narrativeRole: Fifth and last gesture; the climax of the cycle because it removes the keyboard as well as the mouse.
keyMessage: Pinch-hold = talk, and it types.

Adapt: keep prompt-type-submit-generate's signature (text types live into a real product input, the ask IS the show) — but the "keyboard" is a held pinch and the ring's colour says it is listening. No submit; the clip ends with the typed line held.
Scene 1 (0.0–0.5s): kicker swaps "THUMB" → "SPEAK". Right column: a compose window with an empty text field and a blinking caret (`context-sensitive-cursor`).
Scene 2 (0.5–1.1s): the constellation pinches and HOLDS STILL; the ring over the field shrinks, then turns ORANGE with a soft warm orange glow blooming behind it — three tiny sound-level ticks pulse beside it (finite, element-indexed).
Scene 3 (1.1–2.2s): "ship it tonight" types into the field via `type-on with caret` (`discrete-text-sequence`), word by word rather than letter by letter so it reads as speech landing.
Scene 4 (2.2–2.9s): the `lead` line "pinch and hold — speak instead of type." reveals (`per-word staggered reveal`); pinch releases, ring back to teal, typed text stays. Hold.

## Frame 8 — On your Mac

- scene: calm full-frame card — "runs on your mac's camera." / "nothing leaves your mac." with a small mono line "no cloud · no account · no recording"
- voiceover: ""
- duration: 2.8s
- transition_in: blur-crossfade
- status: animated
- src: compositions/frames/08-on-your-mac.html
- type: benefit_highlight
- persuasion: Risk reversal — the objection ("a camera watching me?") answered before it forms
- beat: trust + peace of mind
- blueprint: titlecard-reveal (Reproduce)
- focal: the two-line statement
- roles: statement = cutout · mono line = supporting · ground = background
- asset_candidates:
- sfx: none

narrativeRole: The breather and the trust beat. After five busy gesture frames, stillness is the confidence.
keyMessage: It is private by construction.

Reproduce: one clean two-line title, exactly one restrained move, then a still hold.
Scene 1 (0.0–0.9s): "runs on your mac's camera." slides up ~8% and crossfades in, `h1` role, centered, ~55% width. One move only.
Scene 2 (0.9–1.7s): "nothing leaves your mac." arrives beneath the same way, with "nothing" in teal.
Scene 3 (1.7–2.8s): the `label` line "NO CLOUD · NO ACCOUNT · NO RECORDING" fades in small beneath the statement; everything holds completely still to the cut.

## Frame 9 — AirControl

- scene: the app icon assembles with a teal glow bloom; the wordmark "AirControl" lands beside/below it; tagline "control your mac with a wave of your hand"; the URL small in a pill
- voiceover: ""
- duration: 3.4s
- transition_in: crossfade
- status: animated
- src: compositions/frames/09-aircontrol.html
- type: branding
- persuasion: Identity — name the thing they just watched so they can search for it
- beat: inevitability
- blueprint: logo-assemble-lockup (Adapt)
- focal: registry block `logo-outro` (piece-by-piece assembly, glow bloom, tagline fade-in, URL pill) built around assets/app-icon.png
- roles: app icon (assets/app-icon.png) = cutout · wordmark "AirControl" = cutout · tagline = supporting · URL pill "getaircontrol.vercel.app" = supporting (small — never larger than the wordmark) · ground = background
- asset_candidates: assets/app-icon.png — the app icon: wireframe constellation hand on a dark tile, the closing mark; assets/app-icon-1024.png — same icon at 1024 for a crisp large render
- sfx: impact-soft, riser-short

narrativeRole: The brand outro. The icon is the same constellation hand the viewer has watched for 20 seconds, so the mark explains itself.
keyMessage: It is called AirControl.

Adapt: keep logo-assemble-lockup's signature (the mark comes to exist on screen from parts and resolves into a centered lockup extended to a URL). Use `logo-outro` as the base; the "pieces" are the icon's tile scaling in from 92% with a glow bloom, not a drawn outline.
Scene 1 (0.0–1.0s): the icon lands dead-center (~26% of frame height) with `spring-pop-entrance` (smooth, no overshoot) and a soft teal radial glow blooming up behind it. Nothing else.
Scene 2 (1.0–1.8s): the wordmark "AirControl" (Inter 800, NOT lowercase — it is a name) reveals beneath the icon via `per-word staggered reveal` (two chunks: "Air" "Control"); the icon nudges up slightly to make room (one smooth move).
Scene 3 (1.8–2.5s): the tagline "control your mac with a wave of your hand" fades in beneath in `lead` role, `cream-muted`.
Scene 4 (2.5–3.4s): the URL pill "getaircontrol.vercel.app" fades in small beneath the tagline (`label` role, hairline border); then everything holds still to the end. Last frame is the lockup, held.
