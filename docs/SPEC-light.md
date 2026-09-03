# Spec — Light

The second tab. Answers: *what do I set, and where do I put the zone?*

All maths is specified in [EXPOSURE-MODEL.md](EXPOSURE-MODEL.md). This document is about what the
screen says and how little the user has to touch it.

## The one thing on the screen

The answer, large, at the top, readable at arm's length in sunlight and at night:

```
        f/8 · 1/250 · ISO 400

     scale to 3 m — sharp 1.9 to 7.2 m

        EV 14.1 ± 0.5 · sun 14.7° · 20% cloud
```

Everything else is inputs below it and alternatives beside it. If the user opens the app and reads
only the top three lines, the feature has done its job.

## Inputs, in order of how often they change

| Input | Source | Interaction |
|---|---|---|
| Time | System clock | A scrubber to look ahead — *"what will it be at 18:30?"* |
| Location | CoreLocation | Automatic; overridable by picking a spot from the Map |
| Weather | WeatherKit | Automatic, cached ~15 min, refresh by pull |
| Scene | User | Five-segment control, pre-filled from a selected spot's `openness` |
| Subject lighting | User | Front / side / back — drives §4a. Defaults to front |
| Gear | User | A picker over saved profiles; changes rarely |
| Strategy | User | Zone focus · Freeze motion · Isolate subject · Available light |

Only *scene* and *subject lighting* need touching in normal use, and both are two taps. The gear
profile is set once.

## Gear profiles

Built for a manual rangefinder specifically.

**Body**: name; sensor full-frame (36×24, CoC 0.030 mm); ISO mode — either a **fixed roll speed**
(film) or a **range with a ceiling** (digital); the real shutter ladder; whether it has a meter.

Seed profiles: M6 (1 s–1/1000, film, fixed ISO), M10 (8 s–1/4000, ISO 100–50000), M11 (60 s–1/4000
mechanical, ISO 64–50000).

**Lens**: name; focal length; aperture range and click spacing (half stops on modern M glass); the
**engraved distance marks**; minimum focus.

Seed lenses at 21, 24, 28, 35, 50, 75 and 90 mm, with the marks for each. Getting these right matters
more than it sounds — the whole output is "set the barrel to *this engraved mark*", and a mark the
lens does not have makes the advice unusable.

## Two modes, and they are genuinely different

The body's `medium` decides which of these the screen is. This is not a cosmetic switch — the two
answer different questions, and the maths behind them is in
[EXPOSURE-MODEL.md §7a–7d](EXPOSURE-MODEL.md).

### Analog — the roll is a constraint you live with

ISO is a fact about the film you loaded, not a control. It is set once when the roll goes in, and it
is the reason the app is useful: with two degrees of freedom instead of three, whole scenes are
simply out of reach, and knowing that before you raise the camera is worth more than any exposure
suggestion.

- **Loaded film** is a picker over real stocks, not a bare number. It carries the box speed, the
  medium (B&W neg, colour neg, slide) and therefore the latitude and bias.
- **Rated at** is a separate push/pull control — `HP5 400 @ 1600 (+2)`. Set per roll, shown
  everywhere the ISO appears, with the cost stated ("noticeably coarse grain, blocked shadows").
- ISO renders as **context, not a control** — dimmer than aperture and shutter, because it is not a
  decision you are making right now.
- **The recommendation may be "you can't".** Handled below.

Seed film stocks:

| Stock | Box | Medium | Notes shown |
|---|---|---|---|
| Ilford HP5 Plus | 400 | B&W neg | Pushes to 1600 cleanly — the street default |
| Kodak Tri-X 400 | 400 | B&W neg | Pushes to 1600; more contrast than HP5 |
| Ilford FP4 Plus | 125 | B&W neg | Fine grain, needs light |
| Ilford Delta 3200 | 3200 | B&W neg | Genuinely ISO 1000–1600; rate accordingly |
| Kodak Portra 400 | 400 | Colour neg | Rated conservatively; +1 is common practice |
| Kodak Gold 200 | 200 | Colour neg | Daylight |
| Kodak Ektar 100 | 100 | Colour neg | Bright sun; too slow indoors |
| Fujifilm Provia 100F | 100 | Slide | No latitude. Meter carefully |

The medium column is what sets the solver's tolerance, so it has to be right — a candidate that is
fine on HP5 is a discard on Provia.

### Digital — ISO is the third dial

The solver picks it, up to a **ceiling** the user sets: the point past which they do not want the
file. Ceiling defaults to ISO 6400 and is a plain slider, not a menu.

- ISO renders at **full weight**, alongside aperture and shutter. It is an answer, not context.
- The primary line reads as a change when it is one: *"raise to ISO 1600"* rather than restating a
  value the camera is already on.
- Round up to the body's next real step, never down.
- When the ceiling is not enough, use the same shortfall language as analog rather than silently
  exceeding it.

## When nothing works

The analog solver can return an empty set, and this is a feature. At EV100 5.0 on a dim street, an
HP5 400 roll has **no** handheld solution on an M6.

The screen must not show an empty list or a spinner. It shows the shortfall and the levers:

```
        Not on this roll

  HP5 400 is 0.9 stops short here.

  · Push to 1600 (+2)     f/2 · 1/125
  · Drop to 1/30          accept some blur
  · Wait 20 min           the street lights come up
```

Each lever is tappable and re-solves. The stops-short figure is computed, not hedged. If the gap
exceeds two stops, say plainly that this is the wrong roll for this light — that is the honest
answer and the one a photographer can act on tomorrow.

The mirror case is a roll that is too *fast*: in bright sun an ISO 1600 film overexposes by 1.1
stops even at f/16 · 1/1000. On HP5 that is inside latitude and the app should offer it with a
note; on slide film it is a discard, and the lever is an ND filter.

## Output

**Primary**: one recommendation from the active strategy, in the format above.

**Alternatives**: three or four neighbouring solutions as a horizontal row of cards, each with its
aperture, shutter and resulting zone. Tapping one promotes it to primary. From the worked example in
EXPOSURE-MODEL §7:

```
  f/16 · 1/250        f/11 · 1/500        f/8 · 1/1000
  1.4 m → ∞           1.7 → 14.9 m        1.9 → 7.2 m
```

Seeing the depth collapse as the aperture opens is the thing that teaches the tradeoff.

**Zone focus panel**: the lens's engraved marks as a horizontal scale with the recommended mark
highlighted and the sharp range drawn as a band across it. Dragging to another mark updates the band
live. This is the part worth making beautiful — it is a picture of the lens barrel.

**Sun panel**: elevation, azimuth, time to golden hour and blue hour, and — when a spot is selected —
which side of the street is lit, from `streetBearing`.

## Time scrubbing

A horizontal scrubber across the next 12 hours re-runs the whole model per hour using WeatherKit's
hourly forecast. Small sparklines for EV and sun elevation underneath, with golden and blue hour
shaded.

This turns the feature from a meter into a planning tool: *leave at 18:10, the light hits that
façade at 18:40.*

## Live meter

A button opens a viewfinder-ish view running an `AVCaptureSession`, reading ISO, exposure duration
and aperture to compute a measured EV (EXPOSURE-MODEL §8). Shows model against measured with the
delta, and offers *"Use this as my calibration for shaded streets"*, storing the offset for that
scene type.

Requires camera permission with an honest usage string: *"Used to read the light level for the
exposure advisor. No photos are taken or stored."* And that must remain true — no capture, no
buffers retained.

## Honesty rules

These are behavioural requirements, not polish:

1. **Never show more precision than §9 supports.** "about 1/250", not 1/243.
2. **Always show the uncertainty.** `± 0.5 EV` is part of the answer.
3. **Say when weather is missing or stale**, and widen the uncertainty rather than silently guessing.
4. **Never invent a distance mark.** Only what is engraved on the selected lens.
5. **Back-lit gets a warning, not a number** — the model does not usefully predict a silhouette, and
   the app should say that rather than pretending.

## Offline

Sun position, all the maths, and the entire UI work offline. Only weather does not; without it the
model falls back to clear-sky, adds 0.7 EV to the stated uncertainty, and shows a small
*"no weather"* marker. The screen never blocks on the network.

## Widget (post-v1)

A lock-screen widget showing current EV and the recommended zone-focus setting for the saved gear
profile. This is the feature's natural end state — the answer without unlocking the phone.
