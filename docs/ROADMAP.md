# Roadmap

Milestones are sized so each one is independently verifiable. Every milestone has a matching prompt
in [PROMPT-COPILOT.md](../PROMPT-COPILOT.md).

The ordering is deliberate: the pure maths comes before any UI, because it is the part that can be
proved correct, and it is the part the app's value rests on.

---

### M0 — Scaffold

`project.yml`, six SPM packages, an app target that launches to an empty three-tab shell, CI running
`swift test` on Linux.

**Done when:** `xcodegen generate` produces a project that builds; `swift test` passes on Linux for
the three pure packages; CI is green on the branch.

---

### M1 — `TDMLight`

Solar position, illuminance, EV model, modifiers, DoF, distance-scale snapping, exposure solver.

**Done when:** every test vector in [EXPOSURE-MODEL.md](EXPOSURE-MODEL.md) passes within its stated
tolerance — in particular NYC winter solstice at 25.850°, Sunny 16 at EV 14.64, 50 mm f/8 hyperfocal
at 10.47 m, and the full solve returning f/16 · 1/250 as the zone-focus recommendation.

No UI. No Apple frameworks. Runs on Linux.

---

### M2 — `TDMCore` + `TDMSpots`

Models, bundle codec, integrity check, merge/dedupe, scoring, filtering, search.

**Done when:** the committed fixture bundle round-trips; merge tests over synthetic clusters are
order-independent; scoring reproduces the worked example in [SPOTFORGE.md](SPOTFORGE.md).

---

### M3 — `spotforge`

The pipeline, and a real generated bundle for NYC committed to the repo.

**Endpoints:** the queries in [SPOTFORGE.md](SPOTFORGE.md) have been checked against the current API
references and corrected where they disagreed, but not yet run against the live services — see the
note at the top of that document. The first unsandboxed `spotforge build` is the real smoke test;
fix the document in the same change if a response shape has moved.

**Done when:** `swift run spotforge build --city us-nyc` produces a bundle that `TDMSpots` decodes
and that contains a plausible number of spots per source; pipeline tests run against fixtures with
no network.

---

### M4 — Light screen

The screen from [SPEC-light.md](SPEC-light.md), WeatherKit, gear profiles, the zone-focus scale, the
time scrubber, the live meter.

**Done when:** on a device, the screen gives a correct reading for your current street, the zone
scale shows only marks your lens actually has, and the whole thing works in airplane mode with
widened uncertainty.

This is the first milestone that produces something you can use in the field.

---

### M4a — Analog and digital modes

Adds the dimension M4 does not have. `TDMCore` and `TDMLight` learn the difference between a loaded
roll and a digital sensor: asymmetric film latitude, exposure bias by medium, push and pull, a
no-solution result that explains itself, and ISO as a solved variable on digital. The Light screen
gains the two modes on top.

**Done when:** the eight vectors in [PROMPT-COPILOT.md](../PROMPT-COPILOT.md) M4a pass — in
particular HP5 400 admitting exactly two settings in bright sun, admitting none on a dim street, and
an M10 answering that same street with ISO 1600.

---

### M5 — Map screen

The screen from [SPEC-map.md](SPEC-map.md), bundle download and verification, offline cache, filters,
own pins.

**Done when:** relaunching in airplane mode still shows NYC spots and detail; the *lit now* filter
tracks the sun; a dropped pin survives a bundle refresh.

---

### M6 — Community stub and TestFlight

The local sessions model, the placeholder tab, App Privacy strings, icon, onboarding, first build to
TestFlight.

**Done when:** a build is installable by someone else and the three tabs behave sensibly on a device
that has never run it before.

---

## After v1

- **Lock-screen widget** — current EV and zone-focus setting without unlocking. The natural end state
  of the Light feature.
- **Shot log** — record what you actually set, joined to the spot and the conditions. Over time it
  calibrates the model against your own work, which is better than any generic table.
- **More cities**, driven by where you are going.
- **Community backend** — only once there are people to put in it, and not before the privacy review
  in [SPEC-community.md](SPEC-community.md).
