# The light model

Everything in this document lives in `TDMLight` and is pure, deterministic maths. No network, no
Apple frameworks, no clock. Every number below was computed and cross-checked against independent
references; they are the acceptance criteria for the package.

Every vector here was produced by [`reference/vectors.py`](reference/vectors.py). If you
change the model, run that first and regenerate the tables from its output.

The chain is:

```
time + location ──► solar position ──► ambient illuminance ──► EV100
                                             ▲                   │
                          weather, scene, ───┘                   │
                          subject geometry                       ▼
                                              gear + strategy ──► f/N · shutter · ISO
                                                                  + zone focus range
```

---

## 1. Solar position

Standard NOAA solar position algorithm. Inputs: UTC instant, latitude, longitude. Outputs: apparent
solar elevation (refraction-corrected) and azimuth (degrees clockwise from true north).

```
JD          Julian day
T           (JD − 2451545.0) / 36525
L0          280.46646 + T(36000.76983 + 0.0003032 T)                    mod 360   geometric mean longitude
M           357.52911 + T(35999.05029 − 0.0001537 T)                              geometric mean anomaly
e           0.016708634 − T(0.000042037 + 0.0000001267 T)                          eccentricity
C           sin(M)(1.914602 − T(0.004817 + 0.000014 T))
            + sin(2M)(0.019993 − 0.000101 T) + sin(3M)(0.000289)                   equation of centre
Ω           125.04 − 1934.136 T
λ           L0 + C − 0.00569 − 0.00478 sin(Ω)                                      apparent longitude
ε0          23 + (26 + (21.448 − T(46.815 + T(0.00059 − 0.001813 T)))/60)/60        mean obliquity
ε           ε0 + 0.00256 cos(Ω)                                                     corrected obliquity
δ           asin(sin ε · sin λ)                                                     declination
EoT         4 · degrees(y sin2L0 − 2e sinM + 4ey sinM cos2L0
                        − ½y² sin4L0 − 1¼e² sin2M),  y = tan²(ε/2)                  equation of time, minutes
TST         (minutesUTC + EoT + 4·longitude) mod 1440                               true solar time
HA          TST/4 − 180                                                             hour angle
elevation   90 − acos(sin φ sin δ + cos φ cos δ cos HA)
azimuth     from the standard NOAA branch on sign(HA)
```

Then apply atmospheric refraction to get *apparent* elevation:

| Elevation range | Refraction correction (arcseconds → degrees) |
|---|---|
| `> 85°` | 0 |
| `5° … 85°` | `(58.1/tan h − 0.07/tan³h + 0.000086/tan⁵h) / 3600` |
| `−0.575° … 5°` | `(1735 + h(−518.2 + h(103.4 + h(−12.79 + 0.711h)))) / 3600` |
| `< −0.575°` | `(−20.772 / tan h) / 3600` |

### Test vectors — solar position

| Case | UTC | lat, lon | Expected elevation | Expected azimuth |
|---|---|---|---|---|
| NYC, summer solstice, 12:00 EDT | 2026-06-21 16:00 | 40.7308, −73.9973 | **68.876°** | 219.468° |
| NYC, winter solstice, 12:00 EST | 2026-12-21 17:00 | 40.7308, −73.9973 | **25.850°** | 178.514° |
| NYC, summer solstice, 19:00 EDT | 2026-06-21 23:00 | 40.7308, −73.9973 | **14.727°** | 71.507° |
| Tokyo, equinox, 12:00 JST | 2026-03-20 03:00 | 35.6762, 139.6503 | **54.052°** | 175.289° |
| Berlin, 12:00 CEST | 2026-09-02 10:00 | 52.52, 13.405 | **43.335°** | 202.789° |

Tolerance: ±0.05° on elevation, ±0.2° on azimuth.

> **Independent check.** At the winter solstice, solar elevation at local solar noon is exactly
> `90 − latitude − 23.44°`. For NYC that is `90 − 40.7308 − 23.438 = 25.83°`. The algorithm returns
> 25.850° for 17:00 UTC, which is four minutes off solar noon. Agreement to two hundredths of a
> degree means the declination and equation-of-time terms are both correct. If an implementation
> reproduces this row, it is almost certainly right everywhere.

Derived, and free once the above works: sunrise, sunset, golden hour (`h` from +6° down to −4°) and
blue hour (`h` from −4° to −6°), found by bisection on elevation.

---

## 2. Ambient illuminance

Clear-sky global horizontal illuminance as a function of apparent solar elevation `h`:

```
h > 0.5° :   E = 128000 · (sin h)^1.15          lux
h ≤ 0.5° :   E = 700 · e^(0.885 h)              lux      (twilight decay)
```

The twilight branch is anchored on two published reference points — roughly 700 lux at the horizon
and 3.4 lux at the end of civil twilight (`h = −6°`) — and interpolates exponentially between them.

Below `h = −6°` the daylight model is abandoned entirely; see §5.

## 3. Illuminance → EV

Incident-light metering relation, with calibration constant `C = 250` and `S = 100`:

```
EV100 = log2(E · S / C) = log2(E / 2.5)
```

### Test vectors — ambient EV

| Sun elevation | Illuminance | EV100 (horizontal) |
|---|---|---|
| 90° | 128 000 lux | 15.64 |
| 60° | 108 485 lux | 15.41 |
| 45° | 85 925 lux | 15.07 |
| 40° | 76 999 lux | 14.91 |
| 30° | 57 680 lux | 14.49 |
| 20° | 37 271 lux | 13.86 |
| 10° | 17 094 lux | 12.74 |
| 5° | 7 737 lux | 11.60 |
| 0° | 700 lux | 8.13 |
| −3° | 49 lux | 4.30 |
| −6° | 3.5 lux | 0.47 |

> **Independent check — Sunny 16.** The rule says a front-lit subject in full sun is correctly
> exposed at f/16 and `1/ISO`. At ISO 100 that is f/16 at 1/100, which is
> `log2(16² / (1/100)) = log2(25600) = 14.64`. Note this is **14.64, not 15** — the familiar "EV 15"
> is a rounding. The model must reproduce 14.64, and §4 shows that it does.

## 4. Modifiers

Applied additively in stops, in this order, after the ambient EV100:

### 4a. Subject geometry — the correction that matters most

Ambient illuminance is measured on a *horizontal* surface. A person standing in the street is a
*vertical* surface. When the sun is low, a vertical surface facing it receives dramatically more
light than the pavement does — which is precisely why golden hour is worth shooting.

```
ΔEV_vertical(h) = clamp( log2( cot h ), −1, +3 )        for h > 0.5°, front-lit subject
                = 0                                      otherwise
```

| Sun h | Horizontal EV100 | ΔEV vertical | **Front-lit subject EV100** |
|---|---|---|---|
| 90° | 15.64 | −1.00 | **14.64** |
| 60° | 15.41 | −0.79 | **14.61** |
| 45° | 15.07 | 0.00 | **15.07** |
| 40° | 14.91 | +0.25 | **15.16** |
| 30° | 14.49 | +0.79 | **15.29** |
| 20° | 13.86 | +1.46 | **15.32** |
| 15° | 13.40 | +1.90 | **15.30** |
| 10° | 12.74 | +2.50 | **15.24** |
| 5° | 11.60 | +3.00 | **14.60** |
| 2° | 10.08 | +3.00 | **13.08** |

> **Independent check.** The right-hand column sits between 14.6 and 15.3 at every tabulated
> elevation, and within 14.46 … 15.33 for every sun elevation from 5° to 90° — the shallow minimum
> at 63.4° is what the extra hundredths buy. That is the whole content of Sunny 16: one setting works on a front-lit subject
> all day long. The model reproduces that from first principles rather than being fitted to it, and
> the zenith row lands on 14.64 — the exact Sunny 16 value from §3. This is the strongest single
> check in the document.

Apply this only when the subject faces the light. Side-lit is roughly half the correction, back-lit
is `0` on the subject (and the app should say so, since back-lit street work is a deliberate choice
about silhouettes, not an exposure error).

### 4b. Cloud cover

`c` is WeatherKit `cloudCover`, in `0…1`.

```
ΔEV_cloud = −3.0 · c^1.7
```

| Cover | Δ | From clear EV 15 → | Matches the classic table entry |
|---|---|---|---|
| 0.00 | −0.00 | 15.0 | full sun, distinct shadows |
| 0.25 | −0.28 | 14.7 | slight haze |
| 0.50 | −0.92 | 14.1 | hazy sun, soft shadows |
| 0.75 | −1.84 | 13.2 | cloudy bright, no shadows |
| 1.00 | −3.00 | 12.0 | heavy overcast |

Add a further `−0.5` for light precipitation, `−1.0` for heavy.

### 4c. Scene

The user picks one; it encodes what the sky can actually reach.

| Scene | Δ EV |
|---|---|
| Open sky / sunlit side of the street | 0.0 |
| Shaded side of the street | −2.5 |
| Narrow canyon between tall buildings | −3.5 |
| Under an arcade / deep shade | −4.5 |
| Subway platform / interior | −6.0 |

### 4d. Calibration

A user-stored offset per `(scene, daylight|artificial)` pair, learned from the live meter (§7).
Applied last. Defaults to 0.

### Worked example, end to end

NYC, 21 June 2026, 19:00 EDT. Sun at 14.727° (from §1). Cloud cover 20%.

```
ambient horizontal            EV100 13.37
cloud       −3.0 · 0.20^1.7 =      −0.19
vertical    clamp(log2 cot 14.727°) +1.93
scene       sunlit side              0.0
                                 ─────────
                              EV100 15.10        ← front-lit, sunlit side

scene       shaded side            −2.5
                                 ─────────
                              EV100 12.60        ← same moment, other side of the street
```

Two and a half stops between the two sides of one street. Surfacing that difference is the point of
the feature.

---

## 5. Night and artificial light

Below `h = −6°` the daylight model does not apply and must not be extrapolated. Use presets:

| Situation | EV100 |
|---|---|
| Bright neon / Times Square / illuminated shopfronts | 8 – 9 |
| Well-lit commercial street | 6 – 7 |
| Ordinary residential street | 4 – 5 |
| Dim side street, park path | 2 – 3 |

Between `h = 0°` and `h = −6°`, blend linearly between the daylight value and the selected night
preset. This is the only part of the model that is a lookup rather than a derivation, and the UI
should present it as an estimate to be checked against the live meter.

---

## 6. Depth of field and zone focus

Circle of confusion is a property of the **body**, not a constant, because one M in the roster is
not full frame.

| Format | Bodies | Diagonal | CoC |
|---|---|---|---|
| 35 mm full frame, 36 × 24 | M6, M7, MP, M-A, M9, M10, M11 | 43.27 mm | **0.0300 mm** |
| APS-H, 27 × 18 | **M8** | 32.45 mm | **0.0225 mm** |

CoC scales with the diagonal (`0.030 × 32.45 / 43.27`), which is also what the 1.333× crop factor
gives. Both conventions agree to four decimals, so there is nothing to choose between them.

Configurable per body — 0.025 for a stricter standard — but never hardcoded at a call site.

```
Hyperfocal      H     = f² / (N · c) + f
Near limit      Dn    = s(H − f) / (H + s − 2f)
Far limit       Df    = s(H − f) / (H − s),     ∞ when s ≥ H
```

All distances in mm internally, presented in metres.

### Test vectors — hyperfocal (full frame, c = 0.030 mm)

| Focal | f/4 | f/5.6 | f/8 | f/11 | f/16 |
|---|---|---|---|---|---|
| 28 mm | 6.56 m | 4.69 m | 3.29 m | 2.40 m | 1.66 m |
| 35 mm | 10.24 m | 7.33 m | 5.14 m | 3.75 m | 2.59 m |
| 50 mm | 20.88 m | 14.93 m | 10.47 m | 7.63 m | 5.26 m |

Tolerance ±0.02 m. These agree with standard published hyperfocal tables for full frame.

### Test vectors — the M8 is 33% further out

A smaller CoC means a longer hyperfocal at every aperture. The ratio is constant — `0.030 / 0.0225`
— so **every M8 hyperfocal is exactly 1.333× the full-frame figure**, which is a cheap invariant to
assert in a test.

| Lens | f/ | Full frame | M8 (APS-H) |
|---|---|---|---|
| 28 mm | f/8 | 3.29 m | **4.38 m** |
| 35 mm | f/8 | 5.14 m | **6.84 m** |
| 50 mm | f/8 | 10.47 m | **13.94 m** |

And the zone it actually produces, 35 mm at f/8 set to the 3 m mark:

| Body | Sharp from | Sharp to |
|---|---|---|
| Full frame | 1.90 m | 7.16 m |
| M8 | **2.09 m** | **5.32 m** |

A third less depth than the same lens, same aperture, same mark on a full-frame body. Rendering the
full-frame band for an M8 user would be a quiet, confident lie, which is the worst kind.

### Test vectors — zone ranges

| Lens | Aperture | Scale set to | Sharp from | Sharp to |
|---|---|---|---|---|
| 35 mm | f/8 | 3 m | 1.90 m | 7.16 m |
| 35 mm | f/8 | 5 m | 2.53 m | 183.4 m |
| 35 mm | f/11 | 2 m | 1.31 m | 4.25 m |
| 50 mm | f/8 | 3 m | 2.34 m | 4.19 m |
| 50 mm | f/5.6 | 5 m | 3.75 m | 7.49 m |
| 28 mm | f/8 | 2 m | 1.25 m | 5.05 m |

The 35 mm f/8 at 5 m row is worth keeping as a test: focus sits just under the 5.14 m hyperfocal, so
the far limit explodes to 183 m. An implementation that returns `∞` there has an off-by-one in the
`s ≥ H` branch; one that returns something small has the formula wrong.

### Snapping to the barrel

A rangefinder lens has engraved marks and nothing in between. Model them per lens:

```swift
// Typical Leica M 35mm
distanceMarks: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity]  // metres
```

Two operations:

- **Given a mark and an aperture** → report the sharp range. Used for "what do I get if I set this?"
- **Given a desired range** → find the `(mark, aperture)` pair that covers it, preferring the widest
  aperture that works so the shutter stays fast. Used for "I want 2–6 m sharp."

Always report the range for the **engraved mark**, never for an interpolated distance. A number the
user cannot physically set is worse than useless.

---

## 7. The exposure solver

```
EV_S = EV100 + log2(S / 100)
```

A setting `(N, t)` is correct when `log2(N² / t) = EV_S`.

Enumerate the body's real shutter ladder × the lens's real aperture stops × available ISO, keep
candidates within the medium's tolerance (§7a), then filter by strategy and rank.

**The available ISO is where the two cameras diverge, and it is not a detail.** On a film M the ISO
is a property of the roll you loaded three days ago; the solver has two degrees of freedom and can
legitimately find *none*. On a digital M it is a third variable the solver picks, and it almost
always finds a solution. These are different problems and the app answers them differently — see
§7b and §7c.

### Strategies

| Strategy | Hard constraints | Ranking preference |
|---|---|---|
| **Zone focus** | shutter ≤ handheld floor | smallest aperture that still meters — maximise depth |
| **Freeze motion** | shutter ≤ 1/250 walking, ≤ 1/500 running or close | then widest depth available |
| **Subject isolation** | — | widest aperture; shutter only fast enough to be safe |
| **Available light** | — | lowest ISO that keeps the shutter at the handheld floor |

Handheld floor: `1/focal` as standard, `1/(2·focal)` optionally for a rangefinder (no mirror slap,
so it is genuinely holdable slower — offer it, default it off).

Mild ranking penalty outside f/5.6–f/11 to respect where the lens is sharpest, but never as a hard
constraint.

### Test vector — full solve

Input: EV100 14.05, ISO 400 (film, fixed), 35 mm, zone-focus strategy, handheld floor 1/125.

`EV at ISO 400 = 14.05 + 2 = 16.05`, so `N²/t = 67 847`.

Expected candidates, ranked:

| Setting | Error | Zone at 3 m |
|---|---|---|
| f/8 · 1/1000 | −0.08 EV | 1.9 m – 7.2 m |
| f/16 · 1/250 | −0.08 EV | 1.4 m – ∞ |
| f/11 · 1/500 | −0.17 EV | 1.7 m – 14.9 m |

Under the zone-focus strategy the app recommends **f/16 · 1/250, scale to 3 m — sharp from 1.4 m to
infinity**, and offers the others. That is the sentence the user acts on.

---

## 7a. Tolerance and bias depend on the medium

The ±1/3 stop above is right for a digital sensor and for slide film. It is needlessly strict for
negative film, which is where most of this app's users are.

Every gear profile carries a **medium**, and the medium sets two numbers: how far off a candidate
may be before it is discarded (`latitude`), and where inside that band the solver aims (`bias`).

| Medium | Latitude over / under | Bias | Why |
|---|---|---|---|
| B&W negative — HP5, Tri-X, FP4 | +3.0 / −1.0 | **+0.33** | Expose for the shadows; highlights hold on. |
| Colour negative — Portra, Gold | +3.0 / −1.0 | **+0.66** | Rated conservatively; +1 is common practice. |
| Slide — Velvia, Provia | +0.5 / −1.0 | **−0.33** | No highlight recovery at all. Protect them. |
| Digital raw | +1.0 / −2.0 | **−0.33** | Clipped highlights are gone; shadows lift. |

Two consequences the UI must reflect:

- A candidate 1.1 stops **over** on HP5 is fine and should be offered. The same candidate on Velvia
  is a discard. The solver's tolerance is asymmetric and film-specific, not a flat ±1/3.
- The recommendation is centred on `EV_target = EV_scene − bias`, so on Portra the app deliberately
  suggests two thirds of a stop more light than a meter would. That is correct, and the UI should
  say so once rather than looking like a bug.

**Latitude is not the whole tolerance.** Latitude says what the film will *forgive*; it does not say
what is worth *offering*. A whole-stop aperture ring against a doubling shutter dial cannot land
closer than ±1/3 stop, and a candidate three stops over is not a recommendation, it is a different
photograph. So the solver keeps a candidate when it is inside **both** bands, measured against the
aim:

```
over  = min(latitude.over,  precision − bias)
under = min(latitude.under, precision + bias)
```

with `precision = 1/3 stop` — the ladder's own resolution. Since the band is applied around
`EV_target = EV_scene − bias`, the two biases cancel and the accepted set is exactly ±1/3 stop
around the **meter reading**, *except* where the medium's latitude is tighter than that. Slide is
the case where it is: `min(0.5, 1/3 + (−1/3)) = 1/6` of a stop on the over side, so a candidate that
would be offered on HP5 is refused on Provia — the highlight side, which is the one slide has no
recovery on. Every vector in §7b and §7d was generated under this rule
(`docs/reference/film-vectors.py`).

## 7b. Analog: the solver may legitimately find nothing

With ISO fixed, whole scenes fall outside what a roll can do. This is not an error state — it is the
most useful thing the app can tell a film photographer, and it must be a first-class result rather
than an empty list.

Verified cases, 35 mm on an M6 (1 s – 1/1000), handheld floor as noted:

| Scene | Roll | Result |
|---|---|---|
| Bright sun, EV100 15.10, floor 1/125 | HP5 400 | **2 settings only** — f/16 · 1/500, f/11 · 1/1000 |
| Bright sun, EV100 15.10, floor 1/125 | Ektar 100 | 4 settings — f/16 · 1/125 through f/5.6 · 1/1000 |
| Dim street, EV100 5.0, floor 1/35 | HP5 400 | **none** |
| Dim street, EV100 5.0, floor 1/35 | HP5 pushed to 1600 | 2 — f/2.8 · 1/60, f/2 · 1/125 |
| Dim street, EV100 5.0, floor 1/35 | Delta 3200 | 3 — f/4 · 1/60 through f/2 · 1/250 |

And the case that catches people out: **f/2 for subject isolation in bright sun on ISO 400 needs
1/35 120 s.** No M has that shutter. Even at each body's slowest available ISO, exactly one can
reach it:

| Body | At its slowest ISO | Needs | Top speed | |
|---|---|---|---|---|
| M6 · MP · M-A · M7 | ISO 100 film | 1/8 780 | 1/1000 | no |
| M8 | ISO 160 | 1/14 048 | 1/8000 | no |
| M9 | ISO 80 (pull) | 1/7 024 | 1/4000 | no |
| M10 | ISO 100 | 1/8 780 | 1/4000 | no |
| M11, mechanical | ISO 64 | 1/5 619 | 1/4000 | no |
| **M11, electronic** | ISO 64 | 1/5 619 | **1/16 000** | **yes** |

So the answer is body-specific and the app must not generalise: on an M11 it is a setting, on
everything else it is an ND filter or a slower film. Note the M8 is the *worst* of the digital
bodies here despite the fastest mechanical shutter, because its base ISO 160 costs more than
1/8000 buys back.

When there is no solution, name the shortfall in stops and offer the levers that exist, in this
order:

1. **Push or pull the roll** (§7c) — free, decided in development, costs contrast and grain.
2. **Change the handheld floor or the strategy** — accept 1/30 and some blur, or give up depth.
3. **An ND filter** — when the roll is too fast, which is the bright-sun case.
4. **A different roll** — the honest answer when the gap is more than two stops.

The shortfall is computable and should be stated: at EV100 5.0 an ISO 100 roll is **2.9 stops
short**, ISO 400 is **0.9 short**, and ISO 1600 lands on it.

## 7c. Push and pull

Rating a roll away from box speed is a real field decision and belongs in the app. Pushing HP5 to
1600 is `+2` stops: the solver treats the roll as ISO 1600 and the UI carries the cost.

| Rating | Effect | Cost to state |
|---|---|---|
| Pull 1 stop | Lower contrast, finer grain | Flat negatives; rarely worth it in the street |
| Box speed | — | — |
| Push 1 stop | +1 stop of light | Slightly more contrast and grain |
| Push 2 stops | +2 stops | Noticeably coarse grain, blocked shadows |
| Push 3 stops | +3 stops | Heavy grain, shadows gone — a look, not a fix |

Push applies to the **whole roll**, not the frame, so it is set once alongside the loaded film and
the app must show it wherever the ISO appears: `HP5 400 @ 1600 (+2)`.

## 7d. Digital: ISO is a solved variable

On a digital M the solver picks the ISO, subject to a user-set **ceiling** — the point past which
the user does not want the file. Rank by lowest ISO that satisfies the strategy, not by lowest ISO
outright: a clean frame at 1/30 that is blurred is worse than a noisy one at 1/125.

Verified, dim street at EV100 5.0 on an M10:

| Want | Answer |
|---|---|
| f/2 · 1/125 — freeze a walking subject | **ISO 1600** (1562 exact) |
| f/2 · 1/60 | ISO 800 (750 exact) |

Round the computed ISO **up** to the body's next real step, never down — down means underexposure,
and on digital that is the direction with the least latitude for shadows but the answer people
reach for by habit.

When even the ceiling is not enough, say so with the same shortfall language as §7b rather than
silently exceeding it — **and this is not hypothetical.** The M8 and M9 top out at ISO 2500, which
is two generations behind the M10 and M11:

| Scene | f/2 · 1/125 needs | M8 · M9 (2500) | M10 · M11 (50 000) |
|---|---|---|---|
| Lit street, EV 5.0 | ISO 1 562 | fits | fits |
| Dim side street, EV 3.0 | ISO 6 250 | **short** | fits |
| Near dark, EV 1.0 | ISO 25 000 | **short** | fits |

The no-solution screen is therefore **not analog-only**. An M8 on a dim side street runs out of
sensor exactly the way an HP5 roll runs out of film, and deserves the same honest answer — with a
different set of levers, since pushing is not one of them.

---

## 8. Live meter cross-check

Read `AVCaptureDevice.iso`, `.exposureDuration` and `.lensAperture` from a running capture session
and compute the measured EV:

```
EV100_measured = log2(N² / t) − log2(S / 100)
```

Show model versus measured side by side with the delta. Offer to store the delta as the calibration
offset (§4d) for the current scene type.

This is what keeps the model honest. Sections 2–5 are a physical model plus a lookup table, and
they will be wrong by a stop in some streets. Being wrong by a *consistent* stop that the user can
correct once and forget is an acceptable design; being wrong unpredictably is not — so the
calibration is per scene type, not global.

---

## 9. Presenting uncertainty

Report `EV100 ± σ`:

| Condition | σ |
|---|---|
| Sun above 15°, cloud cover known | 0.5 EV |
| Sun 0–15°, or cloud cover stale | 0.8 EV |
| Twilight blend zone | 1.2 EV |
| Night presets | 1.5 EV |
| No weather data (clear-sky fallback) | add 0.7 EV in quadrature |

Never present more precision than this supports. "f/8, about 1/250" is honest; a recommendation to
1/10 stop is not.
