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

### The body roster

Every M from the M6 forward, because they are all still in daily use and the differences between
them are exactly what this feature exists to know.

| Body | Medium | Format | CoC | Shutter | ISO | Meter |
|---|---|---|---|---|---|---|
| **M6** | film | 36 × 24 | 0.030 | 1 s – 1/1000 | the roll | TTL |
| **M7** | film | 36 × 24 | 0.030 | 32 s – 1/1000 AE · 1/60 + 1/125 without battery | the roll | TTL + aperture priority |
| **MP** | film | 36 × 24 | 0.030 | 1 s – 1/1000 | the roll | TTL |
| **M-A** | film | 36 × 24 | 0.030 | 1 s – 1/1000 | the roll | **none** |
| **M8** | digital | **27 × 18 APS-H** | **0.0225** | 32 s – 1/8000 | 160 – 2500 | TTL |
| **M9** | digital | 36 × 24 | 0.030 | 32 s – 1/4000 | 80 (pull) – 2500 | TTL |
| **M10** | digital | 36 × 24 | 0.030 | 8 s – 1/4000 | 100 – 50 000 | TTL |
| **M11** | digital | 36 × 24 | 0.030 | 60 s – 1/4000 mech · 1/16 000 electronic | 64 – 50 000 | TTL |

These are seed values. Verify each against the manual before shipping — the app's answers are
exactly as good as this table, and a wrong top shutter speed produces confident nonsense.

Three of these are not just different numbers in the same shape:

**The M8 is not full frame.** APS-H, 27 × 18 mm, so its circle of confusion is 0.0225 mm and every
hyperfocal is **1.333× longer** than the full-frame figure. At 35 mm f/8 on the 3 m mark a
full-frame body is sharp 1.90–7.16 m and the M8 is sharp 2.09–5.32 m — a third less depth. The
barrel scale must draw the M8's band, not the full-frame one. It also frames like a 47 mm, which is
worth showing next to the focal length but changes no exposure maths.

**The M-A has no meter at all.** This is the body the app is most useful to: the phone's live meter
(§8) stops being a cross-check and becomes the only meter in the bag. Surface it prominently rather
than as a secondary action, and never phrase anything as "compare with your camera's reading".

**The M7 has aperture priority.** That earns a strategy the mechanical bodies cannot offer: pick the
aperture, let the body choose a stepless shutter. The ±⅓ stop quantisation does not apply in AE, so
the app suggests an aperture and a compensation dial setting rather than a shutter speed. It should
also note the mechanical fallback — without a battery an M7 has 1/60 and 1/125 and nothing else,
which is worth knowing before the battery dies rather than after.

**And the M8 and M9 top out at ISO 2500.** Digital is not automatically unconstrained: on a dim side
street at EV 3.0, f/2 · 1/125 needs ISO 6250 and both bodies are short. The no-solution screen
applies to them too, with levers that do not include pushing.

**Lens**: name; focal length; aperture range and click spacing (half stops on modern M glass); the
**engraved distance marks**; minimum focus.

Seed lenses at 21, 24, 28, 35, 50, 75 and 90 mm, with the marks for each. Getting these right matters
more than it sounds — the whole output is "set the barrel to *this engraved mark*", and a mark the
lens does not have makes the advice unusable.

### The seed catalogue

These are the tables `TDMPersistence.GearCatalogue` writes on first launch. They are the source of
truth: if a mark here is wrong, fix it here and in the catalogue together.

Apertures click in **half stops** on modern M glass, printed with the traditional rounded numbers the
ring is engraved with — f/6.7 rather than f/6.727, which is up to 0.1 stop off an exact half stop and
is deliberately so.

| Body | Shutter | ISO | Notes |
|---|---|---|---|
| Leica M6 | 1 s – 1/1000 | fixed, the loaded roll (default 400) | mechanical; `loadedFilm` names the stock |
| Leica M10 | 8 s – 1/4000 | 100 – 50000 | |
| Leica M11 | 60 s – 1/4000 | 64 – 50000 | mechanical shutter only; the 1/16000 electronic mode is not offered, because it is a mode the photographer has to remember to switch into |

The slow end of the dial is engraved 15, 30 and 60 s — not 16, 32 and 64. A doubling series would
invent speeds the camera has not got.

| Lens | Apertures | Engraved marks (m) |
|---|---|---|
| Super-Elmar-M 21 mm f/3.4 | 3.4 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, ∞ |
| Elmarit-M 24 mm f/2.8 | 2.8 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, ∞ |
| Elmarit-M 28 mm f/2.8 | 2.8 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, 10, ∞ |
| Summicron-M 35 mm f/2 | 2 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, 10, ∞ |
| Summicron-M 50 mm f/2 | 2 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, 10, ∞ |
| APO-Summicron-M 75 mm f/2 | 2 – 16 | 0.7, 0.8, 1, 1.2, 1.5, 2, 3, 5, 10, ∞ |
| Elmarit-M 90 mm f/2.8 | 2.8 – 16 | 1, 1.2, 1.5, 2, 3, 5, 10, ∞ |

Two of these differences are the point of the table rather than an oversight: the 90 mm has **no
0.7 m mark**, because it does not focus that close; and the 21 and 24 mm scales run out at **5 m**
and then go to ∞, because at those focal lengths there is nothing to engrave in between.

Seed profiles pair a body with the lens most likely to be on it: M6 · 35 mm, M10 · 35 mm, M11 ·
50 mm. The first is selected.

Film mode changes the interaction meaningfully: ISO is locked for the whole roll, so the solver has
one fewer degree of freedom and the app should show the roll speed as a fixed fact rather than a
picker. Add a *"loaded film"* field so this is set once when the roll goes in.

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
