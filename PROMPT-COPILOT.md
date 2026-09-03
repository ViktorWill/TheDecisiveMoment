# Kickoff prompts for GitHub Copilot

Seven prompts, one per milestone. Run them **in order** — each assumes the previous one landed.

Paste one at a time into the Copilot coding agent (`github.com/copilot/agents`, or *Assign to
Copilot* on an issue), or into Copilot Chat in Xcode or VS Code. Each is self-contained and names
the spec document it must implement against.

**Why one per milestone rather than one big prompt:** a coding agent given "build me this app"
produces a plausible-looking shell that does not work. Given a bounded task with a stated acceptance
test it produces something you can check. The acceptance criteria in these prompts are the whole
point — do not drop them.

`.github/copilot-instructions.md` is picked up automatically on every task, so the hard constraints
(no Apple imports in the pure packages, no runtime API calls, Swift 6 strict concurrency) do not need
repeating in each prompt.

---

## M0 — Scaffold

```text
Set up the project skeleton for The Decisive Moment, an iOS 18+ SwiftUI app.
Read docs/ARCHITECTURE.md first — it defines the module graph you must follow.

Create:

1. project.yml for XcodeGen defining an iOS app target "TheDecisiveMoment",
   deployment target iOS 18.0, Swift 6 with strict concurrency enabled,
   bundle id com.viktorwill.thedecisivemoment. Do not create or commit an
   .xcodeproj — it is generated, and .gitignore must exclude it.

2. Six Swift packages under Packages/, each with its own Package.swift:
     TDMCore, TDMLight, TDMSpots       — swift-tools-version 6.0, platforms: none
                                          (they must build on Linux), no dependencies
                                          except TDMCore for the latter two
     TDMWeather, TDMPersistence, TDMUI — .iOS(.v18) only
   Dependency direction is strictly as drawn in docs/ARCHITECTURE.md. TDMUI may
   depend on everything; TDMCore depends on nothing.

3. Tools/spotforge — an executable package depending on TDMCore, with a stub
   main that parses --city / --out / --all and prints its plan without doing work.

4. App/ — entry point plus a TabView shell with three tabs (Map, Light, Community),
   each an empty placeholder view. It must launch.

5. .github/workflows/ci.yml — on push and PR: a Linux job running
   `swift test` in Packages/TDMCore, Packages/TDMLight and Packages/TDMSpots.
   Add a macOS job that runs xcodegen and builds the app target, marked
   continue-on-error for now.

6. .gitignore for Swift, Xcode, macOS, and the generated .xcodeproj.

Add one trivial passing test per pure package so CI has something to run.

Acceptance:
- `xcodegen generate` produces a project that opens and builds in Xcode 16.
- `swift test --package-path Packages/TDMLight` passes on Linux.
- The three pure packages import no Apple frameworks — grep them to confirm.
- The app launches to a three-tab shell.
```

---

## M1 — TDMLight (the important one)

```text
Implement Packages/TDMLight. This is the core value of the app: it tells a
photographer using a fully manual rangefinder what to set.

docs/EXPOSURE-MODEL.md is a complete specification with verified numeric test
vectors. Implement it exactly and make every vector pass. Do not redesign the
model, and do not invent expected values — the vectors were computed and
cross-checked against independent references.

Implement, in this order:

1. SolarPosition — NOAA algorithm, §1. Input: Date (UTC), latitude, longitude.
   Output: apparent elevation (refraction-corrected) and azimuth in degrees.
   Also sunrise, sunset, golden hour and blue hour by bisection on elevation.

2. Illuminance — §2 ambient model and §3 EV100 conversion.

3. Modifiers — §4: the vertical-subject correction (4a), cloud attenuation (4b),
   scene presets (4c), and a calibration offset (4d). Order matters.

4. Night — §5 presets and the twilight blend between 0° and −6°.

5. DepthOfField — §6 hyperfocal, near and far limits, plus snapping to a lens's
   engraved distance marks. Both directions: mark+aperture → range, and
   desired range → (mark, aperture).

6. ExposureSolver — §7. Enumerate the body's real shutter ladder against the
   lens's real aperture stops and available ISO, keep candidates within ±1/3
   stop, filter and rank by strategy. Return a primary plus alternatives.

7. Uncertainty — §9.

Tests (swift-testing, @Test/#expect) must cover every table in the document.
These four are the ones that prove correctness — if they pass, the model is right:

  - NYC 2026-12-21 17:00 UTC at 40.7308/−73.9973 → elevation 25.850° ±0.05
    (independent check: 90 − lat − 23.44 = 25.83)
  - f/16 at 1/100, ISO 100 → EV100 14.64 (Sunny 16 — note it is 14.64, not 15)
  - 50mm f/8, CoC 0.030mm → hyperfocal 10.47 m ±0.02
  - EV100 14.05, ISO 400, 35mm, zone-focus strategy, handheld floor 1/125
    → f/16 · 1/250 recommended, sharp 1.4 m to infinity at the 3 m mark,
      with f/11 · 1/500 and f/8 · 1/1000 as alternatives

Units: degrees at API boundaries (radians only inside a function, suffixed Rad),
millimetres for focal length and CoC, metres for focus distance at boundaries,
TimeInterval seconds for shutter. Cite the source and units in a comment above
each formula.

No Apple frameworks. This package must test on Linux.
```

---

## M2 — TDMCore and TDMSpots

```text
Implement Packages/TDMCore and Packages/TDMSpots against docs/DATA-BUNDLES.md
(the wire format) and docs/SPOTFORGE.md §7–8 (merge and scoring).

TDMCore — Sendable Codable value types, with the exact JSON field names from
docs/DATA-BUNDLES.md:
  Coordinate, City, CityIndex, CityIndexEntry, BoundingBox
  Spot, SpotKind, SpotSource, ScoreFactor, SpotPhoto, Openness
  CameraBody, Lens, GearProfile, ISOMode, ExposureStrategy
  ShootSession, Photographer, Visibility  (see docs/SPEC-community.md)
Validation and derived properties only. No behaviour.

TDMSpots:
  - BundleDecoder: gunzip, SHA-256 verify against the index entry, decode.
    A hash mismatch is an error that names the city — never import partial data.
  - SpotMerger: dedupe per §7. Single-link clustering, then reduce each cluster
    once, so the result does not depend on source order. There is a test for this.
  - SpotScorer: per §8, including the log-compressed photo density against the
    city p95 and the featurePrior table. Every term emits a ScoreFactor with
    human-readable detail text.
  - SpotFilter: bounding box, kind, openness, source, score floor, and substring
    search over name and tags.
  - SpotStore protocol — the interface TDMPersistence will implement. Do not
    implement storage here.

Commit Packages/TDMSpots/Tests/Fixtures/us-nyc-sample.json — a complete, valid
two-spot bundle matching docs/DATA-BUNDLES.md, one curated and one OSM-derived,
including photos with author and licence. It is the executable definition of the
schema; the decode test round-trips it.

Acceptance:
- The fixture round-trips byte-identically through decode and encode.
- Merging the same inputs in a shuffled order gives identical output.
- Scoring reproduces the worked example in docs/SPOTFORGE.md §8.
- No Apple frameworks; tests pass on Linux.
```

---

## M3 — spotforge

```text
Implement Tools/spotforge per docs/SPOTFORGE.md. It links TDMCore and writes the
same Spot type the app reads.

BEFORE WRITING CODE: the query URLs in docs/SPOTFORGE.md were written from API
documentation and have NOT been executed — the environment they were authored in
blocked outbound requests to those hosts. Paste each into a browser and confirm
the response shape first. If an endpoint or parameter has changed, update
docs/SPOTFORGE.md in this PR before implementing against it.

Build:
  - data/cities.yml with us-nyc fully specified (districts included).
  - A SpotSource protocol: fetch(bbox:) async throws -> [RawSpot].
  - OverpassSource, WikidataSource, CommonsSource, CuratedSource per the
    document's queries and mappings.
  - Commons: sample a ~250 m grid across the city and accumulate photo counts
    into cells rather than querying per candidate. Note that gsnamespace=6 is
    required — the default namespace returns articles, not files.
  - The six-stage pipeline: fetch → normalise → merge → score → trim → write.
    Reuse TDMSpots' merger and scorer. Do not reimplement them.
  - Disk cache under .cache/ keyed by query hash. One request in flight at a
    time. A descriptive User-Agent with contact info on every request — these
    are volunteer-run services and the policies require it.
  - Output: bundles/v1/index.json and bundles/v1/cities/{id}.json.gz, with
    SHA-256 over the decompressed JSON.
  - `spotforge validate` re-decodes everything and checks hashes.
  - A --report summary: counts per source, merges performed, spots dropped by
    the size cap. A source returning zero results must be loud, not silent.

Also add data/curated/us-nyc.yml with at least eight real, hand-written entries
in the documented format.

Tests run against recorded fixture responses committed under
Tools/spotforge/Tests/Fixtures/. No test may touch the network.

Add .github/workflows/bundles.yml: monthly and manual dispatch only, regenerates
all cities and opens a PR. It must NOT run on push.

Acceptance:
- `swift run spotforge build --city us-nyc --out bundles/v1` produces a bundle
  that TDMSpots decodes, with a plausible spread across all four sources.
- `swift run spotforge validate bundles/v1` passes.
- Tests pass offline.
```

---

## M4 — Light screen

```text
Build the Light tab per docs/SPEC-light.md, plus Packages/TDMWeather and the
gear-profile storage in Packages/TDMPersistence.

The visual design is specified. Read design/Tokens.dc.html for the palette,
type scale, spacing and glyphs, and design/Main.dc.html, design/SunPanel.dc.html
and design/Gear.dc.html for the three screens you are building. They are plain
HTML — lift the exact hex values, sizes, weights, paddings and radii rather than
approximating them, and add no colour that is not in Tokens. design/README.md
explains the two details that are load-bearing rather than decorative.

TDMWeather:
  - WeatherProvider protocol exposing only what the model consumes:
    cloud cover, condition, precipitation intensity, visibility —
    current(at:) and hourly(at:through:).
  - WeatherKitProvider, and StubWeatherProvider for previews and tests.
  - ~15 minute cache. Failure is not fatal: fall back to clear sky and surface
    that to the caller so the UI can widen the stated uncertainty.

TDMPersistence: SwiftData models for GearProfile, CameraBody, Lens and
calibration offsets. Seed on first launch with Leica M6, M10 and M11 bodies and
21/24/28/35/50/75/90mm lenses, each with its real aperture stops and its real
engraved distance marks — see docs/SPEC-light.md. The engraved marks matter:
the app's output is "set the barrel to this mark", so a mark the lens does not
have makes the advice unusable.

UI, per the spec:
  - The answer large at the top: aperture · shutter · ISO, then the zone-focus
    sentence, then EV with uncertainty and conditions. Readable at arm's length
    in sunlight and at night.
  - Alternatives as a horizontal row of cards; tapping one promotes it.
  - The zone-focus panel drawn as the lens barrel: engraved marks along a scale,
    recommended mark highlighted, sharp range as a band. Draggable. Make this
    one beautiful — it is the signature element.
  - Scene and subject-lighting controls (two taps each), gear picker, strategy picker.
  - Sun panel: elevation, azimuth, time to golden and blue hour.
  - A 12-hour time scrubber re-running the model per hour from the hourly
    forecast, with EV and sun-elevation sparklines and golden/blue hour shaded.
  - Live meter: AVCaptureSession reading ISO, exposure duration and aperture to
    compute measured EV; show model vs measured and offer to store the delta as
    the calibration offset for that scene. No frames are captured or retained,
    and the Info.plist usage string must say so truthfully.

Honour the five honesty rules in docs/SPEC-light.md — especially: never show more
precision than the uncertainty supports, and never show a distance mark the
selected lens does not have.

Dark-first. Everything except weather works in airplane mode; without weather,
fall back to clear sky, widen uncertainty by 0.7 EV in quadrature, and show it.

Acceptance: on a device, the screen gives a sane reading for the current street,
the zone scale shows only real marks AND is spaced linearly in 1/distance, the
rendered screen matches design/Main.dc.html side by side, and airplane mode
degrades exactly as described rather than blocking.
```

---

## M4a — Analog and digital modes

```text
Run this AFTER M4 has landed. It adds the dimension M4 does not have: the
difference between a loaded roll and a digital sensor. Read the new
docs/EXPOSURE-MODEL.md sections 7a–7d and docs/SPEC-light.md "Two modes"
and "When nothing works" before changing anything.

TDMCore — add:
  - Medium: .blackAndWhiteNegative, .colourNegative, .slide, .digital
  - FilmStock: name, boxSpeed, medium, note. Seed the eight stocks listed
    in docs/SPEC-light.md.
  - Latitude (over/under stops) and bias, derived from Medium per the table
    in EXPOSURE-MODEL 7a. Do not hardcode these at the call site.
  - LoadedRoll: stock + ratedAt (the push/pull speed), with computed
    pushStops. ISOMode gains .fixed(LoadedRoll) alongside
    .range(min, max, ceiling).

TDMLight — change the solver:
  - Tolerance is asymmetric and comes from the medium, not a constant. A
    candidate 1.1 stops OVER is valid on HP5 and a discard on Provia.
  - Aim at EV_target = EV_scene − bias, so negative film is deliberately
    given more light than a meter would suggest.
  - Return a result type that can express NO SOLUTION, carrying the
    shortfall in stops and the applicable levers (push, floor, ND, other
    roll). An empty array is not acceptable — the reason IS the answer.
  - Digital: solve for ISO subject to the ceiling, rank by lowest ISO that
    satisfies the strategy (not lowest outright), and round UP to the
    body's next real step, never down.

TDMUI — the Light tab becomes two modes, switched on the body's medium:
  - Analog: ISO renders dimmed as context, not a control. Film picker over
    real stocks; a rated-at push/pull control showing "HP5 400 @ 1600 (+2)"
    wherever the ISO appears, with the cost stated.
  - Digital: ISO renders at full weight as a solved value, labelled as a
    change ("raise ISO to 1600"), with a ceiling slider. Mockup:
    design/Digital.dc.html.
  - No-solution is a designed screen, not an empty list, with tappable
    levers that re-solve. Mockup: design/NoSolution.dc.html.
  - Film block on the gear screen: design/Gear.dc.html (updated).

Tests — these are verified, do not adjust them:
  - EV100 15.10, 35mm, M6, floor 1/125, HP5 400 fixed
      → exactly 2 solutions: f/16 · 1/500 and f/11 · 1/1000
  - same scene, Ektar 100 → 4 solutions, f/16 · 1/125 through f/5.6 · 1/1000
  - EV100 5.0, floor 1/35, HP5 400 fixed → NO solution, shortfall 0.9 stops
  - same scene, HP5 rated 1600 → 2 solutions: f/2.8 · 1/60, f/2 · 1/125
  - same scene, Delta 3200 → 3 solutions
  - EV100 5.0, M10, f/2 · 1/125 → ISO 1600 (1562 exact, rounded up)
  - EV100 5.0, M10, f/2 · 1/60 → ISO 800 (750 exact, rounded up)
  - f/2 at EV100 15.10 on ISO 400 needs 1/35120 s → impossible on M6 AND
    M10; the result must say so rather than degrading to a narrower aperture

docs/reference/film-vectors.py generated all of the above; run it to
regenerate them.
```

---

## M4b — The full M body roster

```text
Run this after M4a. It is gear work, so it belongs with the Light tab and
the gear screen, not with the map.

Add every M from the M6 forward: M6, M7, MP, M-A, M8, M9, M10, M11.
docs/SPEC-light.md "The body roster" has the full table — shutter ladders,
ISO ranges, meters, formats. Treat those as seed values and check each
against the manual as you go; a wrong top shutter speed produces confident
nonsense.

Three of them are not just different numbers in the same shape, and each
needs real code, not a row in a list:

1. THE M8 IS NOT FULL FRAME. APS-H, 27 x 18 mm, CoC 0.0225 mm. Circle of
   confusion becomes a property of CameraBody and every depth-of-field call
   takes it from there — grep for 0.030 and remove every hardcoded use.
   Every M8 hyperfocal is exactly 1.333x the full-frame figure; assert that
   ratio as an invariant. The barrel scale must draw the M8's band.
   Also show that a 35mm frames like a 47mm on this body. That is framing
   information only — it changes no exposure maths, so do not let it leak
   into the solver.

2. THE M-A HAS NO METER. This is the body the app matters most to. When the
   selected body has no meter, the phone live meter (EXPOSURE-MODEL section
   8) is promoted from a secondary action to a primary one, and no copy
   anywhere may say "compare with your camera's reading" — there is nothing
   to compare with.

3. THE M7 HAS APERTURE PRIORITY. Add an .aperturePriority strategy available
   only on bodies that support it: the user picks the aperture, the body
   picks a stepless shutter, so the +/-1/3 stop quantisation does not apply
   and the app outputs an aperture plus an exposure-compensation setting
   rather than a shutter speed. Also model the mechanical fallback — with a
   flat battery an M7 has 1/60 and 1/125 and nothing else.

Also: the M8 and M9 ceiling at ISO 2500. The no-solution result from M4a is
NOT analog-only — wire it for digital bodies that run out of sensor, with
levers that do not include pushing.

Mockup for the body picker: design/Bodies.dc.html.

Tests — verified, do not adjust (docs/reference/body-vectors.py regenerates
them):
  - CoC: full frame 0.0300, M8 0.0225 (= 0.030 x 32.45 / 43.27)
  - 35mm f/8 hyperfocal: 5.14 m full frame, 6.84 m on M8
  - 50mm f/8 hyperfocal: 10.47 m full frame, 13.94 m on M8
  - M8 hyperfocal / full-frame hyperfocal == 1.333 for every lens and stop
  - 35mm f/8 at the 3 m mark: 1.90-7.16 m full frame, 2.09-5.32 m on M8
  - f/2 at EV100 15.10 is reachable on the M11 WITH the electronic shutter
    (needs 1/5619 at ISO 64, has 1/16000) and on NO other body, M11
    mechanical included. Do not generalise this either way.
  - f/2 - 1/125 at EV100 3.0 needs ISO 6250: M8 and M9 are SHORT, M10 and
    M11 are fine
```

---

## M5 — Map screen

```text
Build the Map tab per docs/SPEC-map.md, plus bundle storage in
Packages/TDMPersistence.

The visual design is specified: design/Tokens.dc.html for the system,
design/Map.dc.html and design/SpotDetail.dc.html for these two screens. Lift
exact values. Note that the map canvas uses a darker ground (#0B0C0E) than the
rest of the app (#101113) so markers separate against it, and that marker radius
and opacity scale with score — which is why there is no legend.

TDMPersistence:
  - SwiftData models for cached bundles and user pins. Store spots as rows, not
    as a blob, so the map queries by bounding box without loading a whole city.
  - The download flow: fetch index.json (1 hour cache) → resolve the city from a
    coarse location → download the .json.gz → verify SHA-256 → decode → import.
    Any failure keeps the previous bundle and reports which city failed.
  - Implement TDMSpots.SpotStore.

UI:
  - Full-bleed MapKit map, dark style. City chip on top; a draggable sheet at
    three detents below.
  - Clustering above ~2 km visible span. Marker glyph by kind, size and opacity
    by score. Curated spots get an accent colour and draw on top.
  - Filter pills: kind, openness, source, score floor, and "lit now" — computed
    live from solar azimuth against streetBearing using TDMLight. That last one
    is the filter that will actually get used; make it fast.
  - Offline substring search over name and tags.
  - Spot detail sheet: name, distance, the score as prose (never a bare number),
    the curated note in full, a "light right now" strip from TDMLight that opens
    the Light tab pre-filled, bestHours as a 24-hour bar, and photos with author
    and licence beneath each — required, not optional.
  - Long-press drops a pin: name, kind, openness, tags, note, with streetBearing
    pre-filled from device heading. Own pins survive bundle refreshes, are local
    only, and the UI must say they are local only.
  - GeoJSON export of own pins from settings.

Performance: bounding-box queries only, 150 ms debounce on region change, cap at
300 rendered annotations — when a region holds more, raise the effective score
floor and say so rather than dropping markers silently.

No spinner in the offline path: if a bundle is stored, it draws immediately.

Acceptance: relaunch in airplane mode still shows NYC spots and detail; "lit now"
tracks the sun; a dropped pin survives a bundle refresh; "© OpenStreetMap
contributors" is visible on the map surface.
```

---

## M5a — Run without a paid Apple account

```text
The project declares com.apple.developer.weatherkit, so a build signed with
a free Apple ID cannot sign at all. Everything else the app uses — MapKit,
CoreLocation, AVCapture, SwiftData — is free-tier fine, so one entitlement
is the only thing between this app and a phone. Fix that without degrading
the paid build.

Read docs/SPEC-light.md "Sky, when there is no WeatherKit" first.

1. project.yml — add a "Free" build configuration and a matching scheme
   "The Decisive Moment (Free)":
     - CODE_SIGN_ENTITLEMENTS points at a second entitlements file with NO
       WeatherKit key. Do not delete or edit the existing one.
     - SWIFT_ACTIVE_COMPILATION_CONDITIONS adds TDM_NO_WEATHERKIT.
   The default scheme keeps the entitlement and is otherwise unchanged.
   Both must build from one `xcodegen generate`.

2. TDMWeather — add ManualWeatherProvider: no network, builds a
   WeatherObservation from a user-selected sky condition. Map the five
   segments to the cover values in docs/SPEC-light.md exactly; those are the
   EXPOSURE-MODEL §4b rows and must not be re-derived.
   Under TDM_NO_WEATHERKIT do not compile WeatherKitProvider at all, and
   wire ManualWeatherProvider as the only provider — the app must not make a
   network call that is guaranteed to fail with .notAuthorised.

3. TDMUI — the five-segment sky control, styled exactly like the Scene
   control in design/Main.dc.html: same height, hairlines, radii, active
   colour.
     - Free build: always visible, in place of the weather readout.
     - Paid build: the cloud figure in the conditions line becomes tappable
       and opens the same control as an override, with a way back to the
       forecast.

4. The 12-hour scrubber keeps working without a forecast — sun position is
   computed on device. Hold the manual cover constant across the window and
   widen sigma for future hours per EXPOSURE-MODEL §9. Do not hide it.

5. docs/SETUP.md — replace the "you need the paid membership" framing with
   both paths, and state the free-tier realities plainly: the build expires
   after 7 days and must be re-run from Xcode, three sideloaded apps at a
   time, no TestFlight.

Tests:
  - The five segments map to cover 0.0 / 0.25 / 0.5 / 0.75 / 1.0 and produce
    -0.00 / -0.28 / -0.92 / -1.84 / -3.00 EV, matching §4b exactly.
  - Under TDM_NO_WEATHERKIT the WeatherKit import is absent from the built
    module. Assert it at the build level, not in a comment.
  - A manual reading reports sigma 0.5, not the stale-forecast 0.8.
```

---

## M6 — Community stub and TestFlight

```text
Finish v1 per docs/SPEC-community.md.

  - ShootSession and Photographer in TDMCore (they may already be there from M2).
  - The CommunityBackend protocol, and LocalCommunityBackend over SwiftData.
  - A Community tab that lets you create, edit and delete your own sessions as a
    personal shooting plan, optionally anchored to a spot. It explains what the
    section will become. It does NOT show a fake feed or pretend to have people
    in it. Default visibility is private.

Then ship it:
  - App icon and accent colour.
  - Info.plist usage strings — location ("to show spots near you and compute the
    sun's position"), camera ("to read the light level for the exposure advisor;
    no photos are taken or stored"). Both must be true.
  - A privacy manifest declaring what is collected: nothing.
  - Brief onboarding: what the three tabs do, permission requests in context
    rather than up front.
  - Empty states for every list.
  - Dynamic Type and VoiceOver on the primary flows. The exposure readout in
    particular must read sensibly aloud.
  - Remove continue-on-error from the macOS CI job; it should now be required.

Acceptance: a TestFlight build someone else can install, where all three tabs
behave sensibly on a device that has never run the app before, and the Light and
Map tabs work in airplane mode.
```

---

## Reviewing what comes back

The acceptance criteria are checkable, so check them rather than reading the diff for plausibility:

- **M1** — run the tests. The four vectors either pass or they do not. If Copilot changed an expected
  value to make a test pass, that is the failure mode to watch for; the values are correct.
- **M2** — shuffle the merge input order and confirm the output is identical.
- **M3** — open the generated bundle and look at it. Are there spots in Brooklyn? Do the curated
  entries survive? Did any source silently return zero?
- **M4** — take it outside. Compare its recommendation against your meter.
- **M5** — put the phone in airplane mode and relaunch.

The most likely systematic problem across all of them is a degrees/radians slip, which produces
numbers that look reasonable and are wrong. The test vectors are chosen to catch exactly that.
