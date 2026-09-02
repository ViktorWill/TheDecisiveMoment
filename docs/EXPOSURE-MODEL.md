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

Full-frame, circle of confusion `c = 0.030 mm` (configurable; 0.025 for a stricter standard).

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

Enumerate the body's real shutter ladder × the lens's real aperture stops × available ISO (a fixed
roll speed for film, a range for digital). Keep candidates within **±1/3 stop**, then filter by
strategy and rank.

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
