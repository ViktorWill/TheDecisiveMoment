# The Decisive Moment

A field companion for street photography, for iPhone.

Not a portfolio. Not an editor. It is the thing you pull out of your pocket while you are
standing on a corner in a city you don't know, wondering where to walk and what to set your
lens to.

## The three sections

**Map** — the best street-photography spots in whatever city you are currently in, merged from
OpenStreetMap, Wikidata/Wikimedia Commons, a hand-curated canon of places that matter to street
photography, and your own pins. Downloads once per city and then works entirely offline, because
you are usually abroad and roaming when you need it.

**Light** — given the time, the weather and the lens on your camera, what to set and where to put
the zone focus. Built for a manual rangefinder: it tells you *"f/8 · 1/250 · ISO 400 — scale to
3 m, sharp from 1.9 m to 7.2 m."* No auto anything, because your camera has none.

**Community** — later, connecting street photographers who want to go out and shoot the same
city. Modelled in v1, backed by a server in a later phase.

## Status

Design complete. The scaffold (M0) is in place: the module graph exists as six packages under
`Packages/`, a `spotforge` stub under `Tools/`, and an app shell with three empty tabs. The
features themselves are not implemented yet.

Start here:

| Document | What it covers |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | What you need on your Mac and iPhone to build, run and test it |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module graph, data flow, and the reasoning behind every major decision |
| [docs/EXPOSURE-MODEL.md](docs/EXPOSURE-MODEL.md) | The light maths, with verified numeric test vectors |
| [docs/DATA-BUNDLES.md](docs/DATA-BUNDLES.md) | The offline spot-bundle format |
| [docs/SPOTFORGE.md](docs/SPOTFORGE.md) | How bundles get built from public data sources |
| [docs/SPEC-map.md](docs/SPEC-map.md) · [docs/SPEC-light.md](docs/SPEC-light.md) · [docs/SPEC-community.md](docs/SPEC-community.md) | Screen-by-screen behaviour |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones M0–M6 with acceptance criteria |
| [PROMPT-COPILOT.md](PROMPT-COPILOT.md) | Copy-pasteable kickoff prompts, one per milestone |

## Building

Requires a Mac with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen), plus a paid
Apple Developer Program membership from milestone M4 onwards — WeatherKit requires it. Full
requirements in [docs/SETUP.md](docs/SETUP.md).

```sh
brew install xcodegen
xcodegen generate
open TheDecisiveMoment.xcodeproj
```

The pure-logic packages build and test without Xcode:

```sh
swift test --package-path Packages/TDMLight
```

## Target

iOS 18+, Swift 6, SwiftUI. Distributed via TestFlight.
