# Repository instructions for GitHub Copilot

This repository is **The Decisive Moment**, a native iOS field companion for street photography.
Read [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) before making structural changes.

## The specs are the source of truth

Every feature has a written spec under `docs/`. Implement against it. If the spec is wrong or
ambiguous, **fix the spec in the same PR** rather than quietly diverging — a spec that no longer
matches the code is worse than no spec.

| Area | Spec |
|---|---|
| Module layout, decisions | `docs/ARCHITECTURE.md` |
| The light maths + test vectors | `docs/EXPOSURE-MODEL.md` |
| Bundle format | `docs/DATA-BUNDLES.md` |
| Data pipeline | `docs/SPOTFORGE.md` |
| Screens | `docs/SPEC-map.md`, `docs/SPEC-light.md`, `docs/SPEC-community.md` |
| **Visual design** | **`design/Tokens.dc.html`** — palette, type scale, spacing, marker glyphs |
| Screen mockups | `design/Main.dc.html`, `design/SunPanel.dc.html`, `design/Gear.dc.html`, `design/Map.dc.html`, `design/SpotDetail.dc.html` |

## Hard constraints

1. **`TDMCore`, `TDMLight` and `TDMSpots` must not import any Apple framework.** No CoreLocation, no
   SwiftUI, no UIKit, no WeatherKit. Only the cross-platform Foundation subset. These packages build
   and test on Linux in CI, and that is what keeps the logic verifiable. If a change would require an
   Apple import in one of them, the design is wrong — move the platform code to the edge instead.

2. **Never call a spot data source at runtime.** Overpass, Wikidata and Commons are queried only by
   `Tools/spotforge` at build time. Overpass's usage policy forbids client traffic, and the offline
   guarantee depends on this.

3. **Swift 6 strict concurrency.** Model types are `Sendable` value types. No `@unchecked Sendable`
   to silence a warning.

4. **No third-party dependencies** without a note in the PR saying why. The current list is: none.

5. **Never modify `.xcodeproj` directly.** Edit `project.yml` and regenerate.

6. **Attribution is not optional.** OSM-derived data shows "© OpenStreetMap contributors"; Commons
   photos show author and licence adjacent to the image.

7. **The app is used at night.** Dark-first. No white flashes.

8. **Match the mockups.** `design/` holds static mockups as plain HTML. Lift the EXACT values from
   them — hex colours, font sizes, weights, letter-spacing, paddings, radii, control heights, SVG
   glyph geometry. Do not round to an 8pt grid, do not substitute system defaults, and do not
   introduce a colour that is not in `design/Tokens.dc.html`. Open the files and read them; they are
   the visual spec, and they are more precise than a screenshot would be.

   Two details there are load-bearing rather than decorative, and both have a comment in
   `design/README.md`:
   - The distance scale is positioned **linearly in 1/distance**, matching a real engraved Leica
     barrel. Reproduce the spacing, not just the set of marks.
   - Figures are **tabular** everywhere. Use `.monospacedDigit()` so a changing readout does not
     jitter. Prefer `SF Mono` on device over shipping the webfont the mockups use for preview.

## Style

- Swift API Design Guidelines. Clear names over short ones.
- Value types by default. Reference types only where identity is genuinely needed.
- `async`/`await`; no completion handlers, no Combine.
- Errors are typed enums that say what went wrong and what the caller can do about it.
- Comments explain **why**, not what. The formulas in `TDMLight` are the exception — cite the source
  and the units, since a stray degrees/radians conversion is invisible otherwise.
- Match the density and idiom of surrounding code.

## Testing

- `swift-testing` (`@Test`, `#expect`), not XCTest, for new tests.
- Pure packages: assert against the numeric vectors in `docs/EXPOSURE-MODEL.md` and the committed
  bundle fixture. Do not invent expected values — if a vector is missing, compute it, and add it to
  the doc with a note on how it was derived.
- Never write a test that hits the network. Pipeline tests use recorded fixtures.
- A test that needs a simulator belongs in the app target, not in a package.

## Units — the most likely source of bugs

- Angles in **degrees** at API boundaries, radians only inside a function. Name radian variables
  with an `Rad` suffix.
- Focal lengths and circle of confusion in **millimetres**. Focus distances in **metres** at API
  boundaries, converted internally.
- Shutter speeds as `TimeInterval` in seconds — `1/250`, never the integer 250.
- Illuminance in lux. EV values are always **EV100** unless the name says otherwise.

## Definition of done

- Builds with no warnings.
- `swift test` passes for every touched package.
- Spec docs updated if behaviour changed.
- No `TODO` left without an issue reference.
