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
| Weather | WeatherKit, or the photographer | Automatic, cached ~15 min, refresh by pull; five-segment sky control where there is no WeatherKit, and as an override where there is |
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

The slow end is seeded as the **engraved** mark rather than the manual's figure: an M7's AE runs
steplessly to 32 s and an M8's to 32 s, but 30 s is the mark on the dial, and a mark is what the app
can tell someone to set. The dial in `GearCatalogue` is engraved throughout for the same reason —
15, 30 and 60 s, not 16, 32 and 64.

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
| Leica M6 | 1 s – 1/1000 | fixed, the loaded roll (seeded HP5 400) | mechanical; the roll carries the stock, and `loadedFilm` is only for a stock the catalogue has not got |
| Leica M10 | 8 s – 1/4000 | 100 – 50000, ceiling 6400 | |
| Leica M11 | 60 s – 1/4000 mech · 1/16000 electronic | 64 – 50000, ceiling 6400 | electronic speeds are a **lever**, never a default — see below |

**On the M11's electronic shutter.** It is a mode you have to remember to switch into, so it must
never be the default recommendation — that reasoning is right. But excluding it outright costs more
than it saves: 1/16000 is the only way *any* M reaches f/2 in bright sun, which needs 1/5619 at
ISO 64 and is beyond the mechanical 1/4000. Model it the way push is modelled — a lever the app
offers with its condition stated (*"switch to electronic shutter"*), never a speed it silently
assumes you are on. Without it the M4b vector that f/2 in bright sun is reachable on exactly one
body cannot pass.

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

### The film catalogue

A roll is a **stock** plus the speed it is **rated at**. The stock carries the medium, and the medium
carries the latitude and bias the solver works to (EXPOSURE-MODEL §7a) — so choosing Velvia rather
than HP5 changes the answer, not just a label. These eight are seeded; they are the stocks a street
photographer is actually carrying.

| Stock | Box speed | Medium | Why it is here |
|---|---|---|---|
| Ilford HP5 Plus | 400 | B&W negative | The default. Pushes to 1600 without complaint. |
| Kodak Tri-X 400 | 400 | B&W negative | The other default, with more bite. |
| Ilford FP4 Plus | 125 | B&W negative | Slow, fine grain, for bright days. |
| Ilford Delta 3200 | 3200 | B&W negative | Rated 3200; what a dim street asks for. |
| Kodak Portra 400 | 400 | Colour negative | Colour that forgives over-exposure. |
| Kodak Ektar 100 | 100 | Colour negative | Saturated, fine, wants sun. |
| Fujifilm Provia 100F | 100 | Slide | Slide with the least drama. |
| Fujifilm Velvia 50 | 50 | Slide | No highlight recovery at all. Meter it. |

**Rated at** offers whole stops from one pull to three pushes around box speed — for HP5 400 that is
200 / 400 / 800 / 1600 / 3200 — and states the cost of each (EXPOSURE-MODEL §7c). It applies to the
whole roll, not the frame, and is shown wherever the ISO appears: `HP5 400 @ 1600 (+2)`.
Mockup: `design/Gear.dc.html`.

## Two modes

The Light tab is one screen with two behaviours, switched on the body's medium. The difference is
what the ISO *is*, and it is not cosmetic: on film the solver has two degrees of freedom and may find
nothing; on a sensor it has three and almost always finds something.

**Analog** — the body has a roll loaded:

- The ISO is rendered **dimmed, as context, not as a control**. It reads `HP5 400 @ 1600 (+2)`
  wherever a digital body would show a solved ISO, with the cost of the rating stated beside it.
- Changing it means changing the roll, which happens in the film block on the gear screen, not in the
  answer.
- Nothing on the screen invites a tap on the ISO — a roll cannot be changed frame by frame.

**Digital** — the body has a sensor:

- The ISO is rendered at **full weight, in the accent, as a solved value**, and labelled as a change:
  *"Raise ISO to 1600"*. Mockup: `design/Digital.dc.html`.
- An **ISO ceiling** slider sits under the answer, stepping through the body's real full-stop ladder.
  It is the photographer's limit, not the sensor's: past it the file is not worth having, and the
  solver reports a shortfall rather than exceeding it (EXPOSURE-MODEL §7d).
- The alternatives row is labelled *"trade depth for a cleaner file"*, because that is what opening up
  buys on a sensor.

## Sky, when there is no WeatherKit

WeatherKit needs a paid Apple Developer membership, so a build signed with a free Apple ID cannot
carry the entitlement at all — automatic signing refuses it outright. That build is still worth
having, and it should not fall back to clear sky and be wrong by three stops on an overcast day.

Cloud cover is the only weather input the model consumes (§4b), and the person holding the phone is
standing outside looking at the sky. So take it from them:

| Segment | Cover | Δ EV | Straight from the §4b table |
|---|---|---|---|
| Clear | 0.00 | −0.00 | full sun, distinct shadows |
| Light haze | 0.25 | −0.28 | slight haze |
| Hazy sun | 0.50 | −0.92 | soft shadows |
| Cloudy bright | 0.75 | −1.84 | no shadows |
| Overcast | 1.00 | −3.00 | heavy overcast |

Five segments, same shape and styling as Scene, where the weather readout goes.

- **Free build** — the `Free` configuration and the *The Decisive Moment (Free)* scheme, which
  define `TDM_NO_WEATHERKIT`, carry no WeatherKit entitlement and do not compile
  `WeatherKitProvider` at all: the control is the only source, always visible, and
  `ManualWeatherProvider` is the app's only weather provider.
- **Paid build**: WeatherKit leads, and the cloud figure in the conditions line is tappable to
  override it, with *"Use the forecast"* to hand it back. Worth keeping permanently — forecasts are
  wrong, and an observation is fresher than a cached one.

A reported cover is labelled as one — `50% cloud (reported)` — so the conditions line never passes
off an observation as a forecast or the other way round.

Uncertainty stays at 0.5 EV for a manual reading taken now: it is an observation, not a stale
forecast, and claiming otherwise in either direction would be dishonest.

The 12-hour scrubber still works without a forecast — sun position is computed on device, so that
curve is real. Hold cloud cover constant across the window and widen σ for future hours per §9
rather than dropping the feature.

## When nothing works

An empty list is not an answer. When no setting is within tolerance the screen shows the shortfall
and the levers that would close it — the reason *is* the answer. Mockup:
`design/NoSolution.dc.html`.

The screen states, in this order:

1. **What is short, and by how much**: *"HP5 400 is 0.9 stops short here. Nothing on the M6's dial
   reaches it hand-held."* The figure comes from the solver, in stops, against the closest candidate.
2. **The levers**, each a tappable card that re-solves, in the order of EXPOSURE-MODEL §7b:
   - **Push the roll** — the first offer whenever the gap is under two stops. The card names the new
     rating, the stops, and the cost, and carries the setting the push buys.
   - **Drop below the handheld floor** — the next real stop on the dial under the floor, with the
     blur named.
   - **An ND filter** — the bright-sun case, where the roll is too fast rather than too slow.
   - **A different roll** — offered instead of a push once the gap is over two stops.
   - **Raise the ISO ceiling** — digital only, and only when the ceiling rather than the sensor is
     what is in the way.
3. **The two-stop line**: under two stops short the roll is salvageable; past two, the honest answer
   is that this is the wrong film for this light, and that is worth knowing before the frame is burnt.

Tapping a lever applies it — a new rating, a slower floor, a higher ceiling — and the screen re-solves
in place. A lever that does not change the answer is not offered.

The same rule covers the aperture that is off the dial: f/2 in bright sun on ISO 400 needs
1/35 120 s, which no M has. The screen says so and offers the ND, rather than quietly recommending
f/5.6 — that answers a question nobody asked.

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
