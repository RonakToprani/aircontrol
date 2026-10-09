---
format: 1920x1080
duration: 19s
message: "Your Mac, controlled by a wave of your hand."
arc: Hard-hitting graphic — eye opens → two slams → the throw → three gesture hits → the reveal line → the trust line → the sting
audience: Mac users who love new tech — indie devs, designers, the X / TikTok / Product Hunt crowd
mode: autonomous
music: Brainiac (Mixkit, Alejandro Magaña) — assets/bgm-brainiac.mp3, already cut so a hit lands at t=0; 117 BPM, beat 0.513s, bar 2.05s; see ATTRIBUTION.md
---

## Video direction

- **This is a beat-locked graphic ad, not a slideshow.** The music (assets/bgm-brainiac.mp3) is pre-cut so a hit lands at t=0.00. Beat = 0.513s, bar = 2.05s. **Bar lines: 0.00, 2.05, 4.10, 6.15, 8.20, 10.25, 12.30, 14.35, 16.40.** Beats inside a bar: +0.51, +1.03, +1.54. Every frame boundary is a bar or half-bar line; every frame is a HARD CUT (no crossfades anywhere); every major reveal inside a frame lands on a beat. Workers time to these numbers exactly.
- **Apple-grade economy:** 12 words of copy in the whole film. Type is Inter 800 lowercase at display scale (one line fills ~80% of the width); one word per hit; no sentences except the two statement lines. Nothing is labeled, nothing is explained — the picture does the work.
- **One continuous world, at scale.** The two props from the app, drawn huge: (1) the **pointer ring** (thin teal circle with a soft glow; shrinks + brightens on pinch; turns orange when dictating) — at its biggest it is 60% of the frame height; (2) the **hand constellation** — the 21 Vision landmarks (wrist; thumb ×4; index/middle/ring/little ×4 each, open-palm layout in a 380×460 box: wrist (200,420); thumb (150,390)(110,350)(80,310)(58,275); index (150,300)(138,235)(132,190)(128,150); middle (198,290)(196,215)(195,165)(194,120); ring (243,295)(250,225)(253,180)(256,140); little (285,310)(300,255)(308,220)(315,188)) joined by hairlines, dots teal, fingertips brighter and bigger — at its biggest it fills ~75% of the frame height. Poses: open palm; pinch (thumb-tip + index-tip meet near (100,215)); fist (finger chains fold to their knuckles, thumb tucked); thumb-out (fist with the thumb chain swung to point right). Mock windows are flat macOS-style cards (#151B25 surface, 1px #2E3848 border, three dots, title, faint content lines #3A4556) — never screenshots, never browser chrome.
- **Palette (frame.md dark register):** ground #0A0E14, type #F2F5F9, muted #8B94A7, teal #33BFD4 the only accent (orange #F0A050 only while dictating). A single **white impact frame** (1 frame of #F2F5F9 at ~70% opacity, 40ms) is allowed on the two biggest hits (the throw's landing and the wordmark slam) — nowhere else.
- **Motion grammar:** everything arrives on a hit with a long-tail settle (power3 / expo), never bouncy; the camera (a `.world` wrapper) pushes, whips and pulls back — it is a character; motion-blur streaks on the fastest moves; between hits, things HOLD still. No lazy breathing, no drifting particles, no gradients other than the ring's glow.
- **Held frames:** Frame 7 (the reveal line) and Frame 8 (the trust line) hold still after their hit — the stillness is the confidence before the sting.
- **Negative list:** no price, no "free", no "beta"; no labels like POINT/PINCH; no side-by-side "hand here, effect there" layouts; no real cursor arrows; no crossfades; no more than one idea on screen at once. URL appears once, small, last frame.
- **Caption band:** none used; keep type inside the top ~85%.

## Frame 1 — The eye

- scene: black. On the first hit a giant teal ring blooms dead-center; on the next three beats the hand constellation draws itself INSIDE the ring, filling it — the app opening its eye
- voiceover: ""
- duration: 2.05s
- transition_in: cut
- status: animated
- src: compositions/frames/01-eye.html
- type: hook
- persuasion: Visual spectacle — pattern interrupt, no words
- beat: curiosity
- blueprint: logo-assemble-lockup (Adapt)
- focal: the ring + hand constellation at frame scale (hand-authored)
- roles: ring = cutout · hand constellation = cutout · ground = background
- asset_candidates:
- sfx: none

narrativeRole: The hook. A full-frame graphic event on the first hit, before any word.
keyMessage: Something is looking at you.

Adapt: keep the signature (a mark comes to exist from parts and resolves centered) — the "mark" is the ring + hand.
Scene 1 (0.00–0.51s): on the t=0 hit the ring blooms from 0 to ~60% of frame height at dead-center (`spring-pop-entrance`, expo settle, no overshoot) with its glow blooming behind it; its stroke flashes bright white-teal for one frame on the hit then rests teal.
Scene 2 (0.51–1.54s): on beats +0.51 / +1.03 / +1.54 the hand constellation draws on inside the ring in three strokes (`svg-path-draw`): palm bones, then the four fingers, then the thumb + all 21 dots popping on the last beat — the hand fills the ring (~50% of frame height), open palm, fingers up.
Scene 3 (1.54–2.05s): hold. The ring's glow pulses once more on the half-beat and settles. Nothing else.

## Frame 2 — Two slams

- scene: hard cut to type: "no mouse." slams in filling the frame on the bar; "no trackpad." replaces it on the half-bar
- voiceover: ""
- duration: 2.05s
- transition_in: cut
- status: animated
- src: compositions/frames/02-slams.html
- type: hook
- persuasion: Negative contrast — name what's gone
- beat: tension
- blueprint: kinetic-type-beats (Reproduce)
- focal: the two lines (typography only)
- roles: type = cutout · ground = background
- asset_candidates:
- sfx: none

narrativeRole: The words, after the picture. Two hits, two lines, nothing else.
keyMessage: No mouse. No trackpad.

Reproduce: the words ARE the motion — hard-cut swaps on the beat (`kinetic-beat-slam`).
Scene 1 (0.00–1.03s): on the bar hit "no mouse." slams in at display scale (one line ≈ 80% of the width, lowercase, Inter 800), scale 1.12→1 with a 2-frame blur, expo settle; the period is teal. Holds.
Scene 2 (1.03–2.05s): on the half-bar hit it is REPLACED by "no trackpad." — same slam, same place (an in-place swap, not a fade). Holds to the cut.

## Frame 3 — The throw

- scene: inside a desktop at scale: one huge window; the ring arrives on a beat, pinches on the next, and on the bar line the window is RIPPED across the frame with the camera whipping after it; it lands with a white impact frame
- voiceover: ""
- duration: 4.10s
- transition_in: cut
- status: animated
- src: compositions/frames/03-throw.html
- type: product_intro
- persuasion: Show-don't-tell proof at cinematic scale
- beat: awe
- blueprint: camera-journey (Adapt)
- focal: the window + ring, driven by a `.world` camera wrapper
- roles: window = cutout (~55% of frame width at rest) · ring = cutout · a second, smaller window far right = supporting (what the camera reveals on the whip) · dark desktop ground with a faint teal glow = background
- asset_candidates:
- sfx: none

narrativeRole: The product's signature move, shot like an ad, not a tutorial.
keyMessage: It moves windows with nothing touching them.

Adapt: keep camera-journey's signature (the real viewport camera tells the cause→effect story across one continuous world: dive → action → travel → landing push). No cursor; the ring is the hand.
Scene 1 (0.00–0.51s): the camera is pushed IN on a desktop: one window ("Notes") fills ~55% of the width, slightly left; ground has a faint teal radial glow. Still.
Scene 2 (0.51–1.54s): on +0.51 the ring enters from the lower-right on a fast decelerating arc and lands on the title bar; on +1.03 it PINCHES — shrinks to 65%, brightens, the window gets the 1px teal ghost outline and lifts (a quick compress-then-settle, smooth, no bounce).
Scene 3 (2.05–3.08s): on the bar line (2.05) the THROW: window + ring rip to the right ~1.4 frame-widths while the camera (`viewport-change` on the `.world`) whips right with them, a heavy horizontal `motion-blur-streak` on the window and the ground for ~250ms; a second smaller window ("Inbox") streaks past underneath. At 3.08 (next half-bar) the window LANDS: one white impact frame (40ms), the ring releases to full size, the window settles with a deepening-then-relaxing shadow.
Scene 4 (3.08–4.10s): hold on the landed window, the camera eases back ~6% (one pull, then still). The ring idles. Cut.

## Frame 4 — Fist

- scene: a giant fist constellation fills the left of the frame; on the beat a document window behind it rips upward in a scroll blur and coasts; one word, small: "scroll."
- voiceover: ""
- duration: 1.03s
- transition_in: cut
- status: animated
- src: compositions/frames/04-fist.html
- type: feature_showcase
- persuasion: Show-don't-tell proof, one hit
- beat: power
- blueprint: kinetic-type-beats (Adapt)
- focal: the fist constellation at ~70% frame height, overlapping a tall document window behind it
- roles: fist constellation = cutout (left 55%) · document window = supporting (behind, right 60%, overlapped) · word = supporting
- asset_candidates:
- sfx: none

narrativeRole: Gesture hit 1 of 3 — half a bar each, same grammar: pose, effect, one word.
keyMessage: Fist = scroll.

Adapt: the "words are the motion" shape, but the beat is a pose + an effect; the single word is the tail.
Scene 1 (0.00–0.26s): on the cut the fist constellation is ALREADY there, huge (~70% of frame height, centered-left, thumb tucked), dots teal; the document window sits behind it to the right, overlapped.
Scene 2 (0.26–0.77s): on +0.26 the document's rows rip UPWARD with a vertical `motion-blur-streak` (~1.5 window heights) then coast with an expo tail; the ring on the window is indigo while it moves.
Scene 3 (0.77–1.03s): the word "scroll." appears lower-left (`label`-sized, muted, lowercase, no animation beyond a 2-frame fade). Cut.

## Frame 5 — Thumb

- scene: the fist opens its thumb sideways; on the beat the ENTIRE frame — ground, window and all — slides left as the next desktop slams in from the right; one word: "switch."
- voiceover: ""
- duration: 1.03s
- transition_in: cut
- status: animated
- src: compositions/frames/05-thumb.html
- type: feature_showcase
- persuasion: Show-don't-tell proof, one hit
- beat: delight
- blueprint: kinetic-type-beats (Adapt)
- focal: the thumb-out constellation at ~70% frame height; the whole world push-slides behind/with it
- roles: constellation = cutout · current desktop (one window) = supporting · next desktop (two windows) = supporting · word = supporting
- asset_candidates:
- sfx: none

narrativeRole: Gesture hit 2 of 3.
keyMessage: Thumb = next desktop.

Adapt: same half-bar grammar; the effect is the whole frame moving.
Scene 1 (0.00–0.26s): the fist constellation from Frame 4's position, thumb chain swinging OUT to point right over 0.2s (the rest of the hand holds).
Scene 2 (0.26–0.77s): on +0.26 the entire world (a `.world` wrapper holding the desktop: ground tint, window, everything except the constellation and the word) push-slides LEFT out of frame as the next desktop (two smaller windows, "Mail" and "Calendar") slams in from the right with a horizontal `motion-blur-streak`, expo settle. The constellation stays put — the hand is the camera's anchor. A tiny teal "space →" flashes once at the top center.
Scene 3 (0.77–1.03s): "switch." lower-left. Cut.

## Frame 6 — Speak

- scene: the constellation pinches and HOLDS; the ring goes huge and orange; "ship it tonight" types itself across the frame at display scale, word by word on the beats; one word: "speak."
- voiceover: ""
- duration: 2.05s
- transition_in: cut
- status: animated
- src: compositions/frames/06-speak.html
- type: feature_showcase
- persuasion: Feature-to-benefit — the keyboard is gone too
- beat: awe
- blueprint: typewriter-reveal (Adapt)
- focal: the giant orange ring (~45% frame height, upper-center) and the typed line at display scale beneath it
- roles: ring = cutout · pinch constellation = supporting (lower-left, ~35% frame height) · typed line = cutout · word = supporting
- asset_candidates:
- sfx: none

narrativeRole: Gesture hit 3 of 3 — a full bar, because the typed words need their beats.
keyMessage: Hold a pinch, talk, it types.

Adapt: keep the signature (a line types as a human would and pays off) — here the words land one per beat, at display scale, no caret.
Scene 1 (0.00–0.51s): the constellation (lower-left, ~35% frame height) pinches on the cut and holds; the ring, upper-center at ~45% frame height, shrinks a touch then turns ORANGE with a soft warm glow blooming behind it — listening.
Scene 2 (0.51–1.54s): on +0.51 / +1.03 / +1.54 the words "ship" / "it" / "tonight" land across the frame beneath the ring at display scale (Inter 800 lowercase, each word a slam with a 2-frame blur, expo settle, `kinetic-beat-slam`) — the line reads "ship it tonight" by the third beat.
Scene 3 (1.54–2.05s): "speak." lower-left; the ring eases back to teal. Cut.

## Frame 7 — Your Mac can see

- scene: "your mac can see your hand." fills the frame; as it lands, the camera pulls back and the hand constellation is revealed BEHIND the words at full frame scale, the ring resting on its index fingertip
- voiceover: ""
- duration: 2.05s
- transition_in: cut
- status: animated
- src: compositions/frames/07-see.html
- type: product_intro
- persuasion: Future pacing — the new fact, stated once
- beat: clarity + aspiration
- blueprint: zoom-out-workspace-reveal (Adapt)
- focal: the statement, then the full-frame hand constellation behind it
- roles: statement = cutout · hand constellation = cutout (behind, dimmed to ~55%) · ring = supporting
- asset_candidates:
- sfx: none

narrativeRole: The message, in the viewer's language, over the product's own geometry.
keyMessage: Your Mac can see your hand.

Adapt: keep the signature (ONE decelerating zoom-out reveals the containing whole) — the whole is the hand.
Scene 1 (0.00–0.51s): on the bar hit the line "your mac can see your hand." slams in, two lines, display scale, centered (`kinetic-beat-slam`); "hand" teal.
Scene 2 (0.51–1.54s): one continuous decelerating camera pull-back on the `.world` (`viewport-change`) reveals the hand constellation behind the type at ~85% of frame height, dimmed, open palm, the ring resting on the index fingertip — it was there all along.
Scene 3 (1.54–2.05s): hold. Still.

## Frame 8 — Nothing leaves

- scene: one line, still: "nothing leaves your mac." with "nothing" in teal; beneath, tiny: "no cloud · no account · no recording"
- voiceover: ""
- duration: 2.05s
- transition_in: cut
- status: animated
- src: compositions/frames/08-nothing.html
- type: benefit_highlight
- persuasion: Risk reversal — the camera objection answered in five words
- beat: trust
- blueprint: titlecard-reveal (Reproduce)
- focal: the line
- roles: line = cutout · small line = supporting · ground = background
- asset_candidates:
- sfx: none

narrativeRole: The breather before the sting. Stillness is the confidence.
keyMessage: It is private by construction.

Reproduce: one restrained move, then a still hold.
Scene 1 (0.00–0.51s): on the bar hit the line arrives with ONE move — a short rise + fade, expo — display scale, centered.
Scene 2 (0.51–2.05s): the small mono line fades in beneath on +0.51; then nothing moves at all.

## Frame 9 — The sting

- scene: the app icon lands on the hit; the wordmark "AirControl" SLAMS to scale with one accent ring and one white impact frame (logo-sting); tagline and the URL pill settle beneath; hold
- voiceover: ""
- duration: 2.60s
- transition_in: cut
- status: animated
- src: compositions/frames/09-sting.html
- type: branding
- persuasion: Identity — name it so they can search it
- beat: inevitability
- blueprint: logo-assemble-lockup (Adapt)
- focal: registry component `logo-sting` (wordmark slam + accent ring + white impact frame) with the icon (assets/app-icon-1024.png) above it
- roles: icon = cutout · wordmark = cutout · tagline = supporting · URL pill = supporting (smaller than the wordmark) · ground = background
- asset_candidates: assets/app-icon-1024.png — the app icon at 1024 (dark rounded tile, wireframe constellation hand), no extra tile around it; assets/app-icon.png — 512 variant
- sfx: none

narrativeRole: The brand outro — hard, then still.
keyMessage: It is called AirControl.

Adapt: keep the signature (the mark comes to exist and resolves into a centered lockup extended to the URL) using logo-sting's slam mechanics inline.
Scene 1 (0.00–0.51s): on the bar hit the icon lands dead-center at ~30% frame height (`spring-pop-entrance`, expo, no overshoot) with a teal glow bloom behind it.
Scene 2 (0.51–1.03s): on +0.51 the wordmark "AirControl" (Inter 800, NOT lowercase) SLAMS beneath it from 1.6× to 1× scale; a single teal accent ring expands from behind the wordmark and fades; ONE white impact frame (40ms) on the hit. The icon nudges up to make room (one smooth move).
Scene 3 (1.03–1.54s): the tagline "control your mac with a wave of your hand" (muted, lowercase) and then the small URL pill "getaircontrol.vercel.app" settle beneath.
Scene 4 (1.54–2.60s): hold completely still to the end.
