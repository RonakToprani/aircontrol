# The viral re-cut — what to film (≈2 minutes of your time)

The current cut is a clean explainer. It cannot go viral because nothing on screen is real.
Viral for this product = a real hand, a real Mac obeying it, and a "no way" moment in the first second.

## Record ONE take, ~45–60s, no talking needed

Sit at the Mac, decent light, AirControl ON, mouse mode ON. Record the SCREEN and the WEBCAM at the same time
(webcam shows your hand; screen shows the Mac reacting). Either:

- QuickTime: File → New Screen Recording (whole screen) AND File → New Movie Recording (camera) — start both, do the take, stop both. Two files, same take.
- or one command (terminal; grant camera/screen access when asked), which writes screen.mp4 and cam.mp4:

      ffmpeg -f avfoundation -framerate 30 -capture_cursor 0 -i "Capture screen 0" screen.mp4 \
             -f avfoundation -framerate 30 -i "FaceTime HD Camera" cam.mp4

Then drop both files in videos/aircontrol-promo/footage/ and say "cut it".

## The take, in order (do each gesture BIG and slow — the camera needs 1s per move)

1. Hand enters frame, open palm. Move it left/right — the cursor follows. (3s)
2. Pinch a Finder/Notes window by its title bar, DRAG it across the whole screen, release. This is the hero shot; do it twice. (6s)
3. Fist → scroll a long page (a website) up and down. (5s)
4. Fist with thumb sideways → desktop switches. Do it twice, left and right. (5s)
5. Pinch-hold on a text field, SAY a sentence ("ship it tonight"), watch it type. (6s)
6. Lower your hand, lean back, open your palm toward the camera like "that's it". (3s)

Optional but powerful: a second angle — phone on the desk filming you + the screen in one shot (the "proof" angle).

## How the re-cut uses it (what I will build)

- 0.0–1.0s  HOOK: real pinch-and-throw of the window, cropped tight, no text, sound hit.
- 1.0–2.0s  "no mouse. no trackpad." slams over the freeze.
- 2–18s     the five gestures, real footage with the webcam as a corner PiP (hand) and kinetic labels POINT / PINCH / FIST / THUMB / SPEAK.
- 18–21s    "runs on your mac's camera. nothing leaves your mac."
- 21–25s    icon + AirControl + URL.
Vertical 9:16 becomes natural: webcam on top, screen on the bottom.
