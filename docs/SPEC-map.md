# Spec — Map

The first tab. Answers one question: *where should I walk from here?*

## Layout

A full-bleed MapKit map. No chrome competing with it.

- **Top**: a city chip — `New York City · 842 spots · offline` — tapping it opens the city picker.
- **Bottom**: a draggable sheet at three detents. Collapsed shows a search field and filter pills;
  medium shows the ranked list of nearby spots; large is the full list.
- **Floating, bottom-right**: recentre button, and a sun toggle that overlays the current solar
  azimuth.

Dark map style by default. This gets used at dusk.

## City detection

1. On launch, get a coarse location (`kCLLocationAccuracyKilometer` is enough and is cheaper and
   more private than precise).
2. Fetch `index.json`, find the city whose `bbox` contains the coordinate. If several match, take
   the nearest `center`.
3. If that city's bundle is stored and current, load it. If not, show a download prompt with the
   size: *"New York City — 842 spots, 180 KB. Download."*
4. If no city matches, say so plainly — *"No spot data for this area yet"* — and show the user's own
   pins. Offer the city picker so they can look at somewhere else.

The city picker lists all cities from `index.json`, sorted by distance, with download state and size
per row. Downloading a city you are not in is a first-class action: you plan a trip on the sofa, you
use it in the street. It should also be possible to pre-download over Wi-Fi with an explicit
*"Download for offline"* action per city.

## Annotations

Individual spots below ~2 km of visible span; clustered above it. Cluster bubbles show a count and
adopt the colour of their highest-scoring member.

Marker glyph is by `kind` (SF Symbols: `building.columns` plaza, `cart` market, `figure.walk`
street, `stairs` stairs, `tram` transit …). Marker size and opacity scale with `score` — the good
stuff is visibly bigger without needing a legend.

Curated spots get a distinct accent colour and always render above generated ones.

Optional **photo-density heatmap** layer from the Commons grid, off by default. It is atmospheric
rather than precise, and should be labelled as such.

## Filters

Pills in the collapsed sheet, multi-select, persisted between launches:

- **Kind** — plaza, market, street, stairs, transit, …
- **Openness** — open / canyon / covered
- **Source** — curated only · include generated · my pins
- **Lit now** — computed live from solar azimuth against `streetBearing`; hides spots currently in
  shadow. This is the filter that will actually get used.
- **Score floor** — a slider, default 0.3.

Search is a plain substring match over `name` and `tags`, offline, no network.

## Spot detail

Opens as a sheet over the map.

- Name, kind, distance and walking time.
- The score, **as prose**: *"137 geotagged photos nearby · marketplace · curated"*. Never the bare
  number.
- The curated `note` where there is one, in full, unclipped. It is the most valuable thing on the
  screen.
- **Light right now** — a compact strip pulling from `TDMLight`: sun elevation and azimuth, which
  side of the street is lit (from `streetBearing`), and the recommended exposure for this spot's
  `openness`. Tapping it opens the Light tab pre-filled with this spot.
- `bestHours` as a small 24-hour bar with the current hour marked.
- Photos, if any, with author and licence beneath each — required, not optional.
- Actions: *Directions* (hands off to Maps), *Save*, *Mark as visited*, *Add a note*.

Personal notes and visit state are local, keyed by spot `id`, and survive a bundle update — which is
why ids have to be stable.

## Your own pins

A long-press on the map drops a pin. The sheet asks for name, kind, openness, tags and a note, and
pre-fills `streetBearing` from the device heading if available.

Own pins render distinctly, are never removed by a bundle refresh, and are included in filters and
search. They are stored only on the device in v1 — this is stated in the UI, because the natural
assumption is that they sync.

Export as GeoJSON from settings, so the data is never trapped.

## Offline behaviour

Everything above works with no network, except the *Light right now* strip, which falls back to a
clear-sky estimate and says so. Map tiles themselves come from MapKit and are the one thing that
genuinely needs a connection; when tiles fail, the annotations still render over an empty grid and a
banner explains that only tiles are missing.

There is no spinner anywhere in the offline path. If data is stored, it draws immediately.

## Performance

- Bounding-box query in SwiftData against the visible rect, not a full-city load.
- Debounce region changes by 150 ms.
- Cap rendered annotations at 300; when a region holds more, raise the effective score floor and say
  so subtly rather than dropping markers silently.
