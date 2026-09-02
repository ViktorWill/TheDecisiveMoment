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
the zone scale shows only real marks, and airplane mode degrades exactly as
described rather than blocking.
```

---

## M5 — Map screen

```text
Build the Map tab per docs/SPEC-map.md, plus bundle storage in
Packages/TDMPersistence.

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
