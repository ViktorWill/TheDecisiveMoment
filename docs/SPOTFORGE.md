# spotforge — the bundle pipeline

A Swift command-line executable at `Tools/spotforge`. It runs at build time — never on a phone —
and turns four sources into the city bundles described in [DATA-BUNDLES.md](DATA-BUNDLES.md).

```sh
swift run spotforge build --city us-nyc --out bundles/v1
swift run spotforge build --all --out bundles/v1
swift run spotforge validate bundles/v1
```

It links `TDMCore`, so it writes the same `Spot` type the app decodes. The schema cannot drift.

> ### Before implementing: smoke-test the endpoints
>
> The query URLs below were written from documentation, **not executed** — the environment they were
> authored in blocks outbound requests to these hosts. Paste each into a browser and confirm the
> shape of the response before writing code against it. If one has changed, fix this document first.

## Stages

```
  ┌─────────┐   ┌─────────┐   ┌────────┐   ┌───────┐   ┌───────┐   ┌────────┐
  │ 1 fetch │──►│ 2 norm. │──►│ 3 merge│──►│4 score│──►│5 trim │──►│6 write │
  └─────────┘   └─────────┘   └────────┘   └───────┘   └───────┘   └────────┘
   per source    → Spot        dedupe       0…1 norm.   size cap    gz + sha
```

Each source sits behind a `SpotSource` protocol with a single `fetch(bbox:) async throws -> [RawSpot]`.
Tests use recorded fixtures, never the live network — the pipeline must be testable offline and must
not hammer volunteer-run infrastructure in CI.

Every run writes a `--report` summary: spots per source, merges performed, spots dropped by the size
cap, and any source that returned nothing. A source silently returning zero results is the most
likely failure mode and must be loud.

---

## 1. Cities

Cities are declared in `data/cities.yml`:

```yaml
- id: us-nyc
  name: New York City
  country: US
  center: { lat: 40.7128, lon: -74.0060 }
  bbox:   { minLat: 40.4774, minLon: -74.2591, maxLat: 40.9176, maxLon: -73.7004 }
  districts:
    - { name: Manhattan, bbox: { minLat: 40.6980, minLon: -74.0200, maxLat: 40.8800, maxLon: -73.9070 } }
    - { name: Brooklyn,  bbox: { minLat: 40.5700, minLon: -74.0420, maxLat: 40.7395, maxLon: -73.8330 } }
```

Districts exist so Overpass queries stay under the timeout on large cities, and so the UI can say
"12 new spots in Brooklyn" rather than treating a city as one undifferentiated blob.

---

## 2. Overpass / OpenStreetMap

Free, no key, global coverage. This is the backbone: it is what makes a city the app has never seen
still be useful.

**Endpoint:** `https://overpass-api.de/api/interpreter` (POST, body is the query)

**Usage policy matters here.** Overpass is volunteer-run. Rate-limit to one request at a time, set a
descriptive `User-Agent`, cache responses to `.cache/overpass/` keyed by query hash, and never call
it from the app. Prefer `https://overpass.kumi.systems/api/interpreter` as a fallback endpoint.

```
[out:json][timeout:180];
(
  node["highway"="pedestrian"]({{bbox}});
  way ["highway"="pedestrian"]({{bbox}});
  way ["highway"="footway"]["footway"="crossing"]({{bbox}});
  node["amenity"="marketplace"]({{bbox}});
  way ["amenity"="marketplace"]({{bbox}});
  way ["place"="square"]({{bbox}});
  node["place"="square"]({{bbox}});
  way ["man_made"="bridge"]({{bbox}});
  way ["highway"="steps"]({{bbox}});
  way ["tunnel"="yes"]["highway"]({{bbox}});
  way ["covered"="yes"]["highway"]({{bbox}});
  node["tourism"="viewpoint"]({{bbox}});
  node["railway"="station"]({{bbox}});
  node["public_transport"="station"]({{bbox}});
  way ["leisure"="park"]({{bbox}});
  way ["natural"="coastline"]({{bbox}});
);
out center tags;
```

`out center` gives a single representative coordinate for ways, which is what the map needs.

### OSM tag → `kind`

| OSM tags | `kind` |
|---|---|
| `place=square`, `highway=pedestrian` (area) | `plaza` |
| `amenity=marketplace` | `market` |
| `highway=pedestrian` (linear) | `street` |
| `man_made=bridge`, `bridge=yes` | `bridge` |
| `highway=steps` | `stairs` |
| `tunnel=yes` | `underpass` |
| `covered=yes`, `building=arcade` | `arcade` |
| `railway=station`, `public_transport=station` | `transit` |
| `natural=coastline`, `waterway` adjacency | `waterfront` |
| `leisure=park` | `park` |
| `tourism=viewpoint` | `viewpoint` |
| otherwise | `other` |

### Derived fields from OSM

- **`streetBearing`** — for a way, the bearing of the line between its first and last node,
  normalised to 0–180°.
- **`openness`** — `covered` when `tunnel=yes` or `covered=yes`; `canyon` when the mean height of
  buildings within 30 m exceeds ~25 m (use `building:levels` where present, otherwise leave `open`);
  `open` otherwise. Be conservative — a wrong `canyon` costs the user 3.5 stops.

---

## 3. Wikidata

Notable places, giving the "famous spots in Manhattan" layer.

**Endpoint:** `https://query.wikidata.org/sparql` (`Accept: application/sparql-results+json`)

```sparql
SELECT ?item ?itemLabel ?coord ?sitelinks WHERE {
  SERVICE wikibase:box {
    ?item wdt:P625 ?coord .
    bd:serviceParam wikibase:cornerSouthWest "Point(-74.2591 40.4774)"^^geo:wktLiteral .
    bd:serviceParam wikibase:cornerNorthEast "Point(-73.7004 40.9176)"^^geo:wktLiteral .
  }
  ?item wikibase:sitelinks ?sitelinks .
  FILTER(?sitelinks > 5)
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}
```

`sitelinks` — the number of Wikipedia language editions with an article — is the notability signal.
It is crude but robust, and far better than nothing. A `User-Agent` with contact information is
required by the WDQS policy.

---

## 4. Wikimedia Commons — photo density

The most interesting signal in the pipeline: **where have people actually stood and made pictures.**

**Endpoint:** `https://commons.wikimedia.org/w/api.php`

```
https://commons.wikimedia.org/w/api.php
  ?action=query
  &list=geosearch
  &gscoord=40.7308%7C-73.9973
  &gsradius=500
  &gsnamespace=6          ← File namespace. Without this you get articles, not photos.
  &gslimit=500
  &format=json
```

`gsnamespace=6` is the part people get wrong; the default namespace 0 returns articles and the query
looks broken. Radius caps at 10 km, limit at 500.

Rather than one query per candidate spot — which would be thousands of requests — sample a grid
across the city at ~250 m spacing, accumulate counts into cells, and read each candidate's density
from its cell plus its eight neighbours. One pass, bounded cost, and the resulting grid is also what
draws the heatmap layer.

For the top-scoring spots, fetch representative images with `prop=imageinfo` and
`iiprop=url|extmetadata` to get `thumbURL`, `pageURL`, author and licence. **Store the licence.** A
photo without attribution does not go in the bundle.

## 5. Curated canon

Hand-written YAML at `data/curated/{cityId}.yml`. Small, slow-growing, and the reason the app reads
like it was made by someone who shoots.

```yaml
- name: Fifth Avenue & 42nd Street
  lat: 40.75350
  lon: -73.98130
  kind: intersection
  tags: [crowds, canyon-light, midtown, commuters]
  openness: canyon
  streetBearing: 15
  bestHours: [8, 9, 17, 18]
  note: >
    Winogrand worked this stretch for years. The crosstown blocks let light through
    twice a day; the avenue itself is in shadow most of the time. Stand on the
    northeast corner and shoot back into the crowd coming off the light.
  score_boost: 0.25
```

Curated entries never get dropped by the size cap and always carry `curated: true`. `score_boost`
is added before normalisation.

This file is the app's soul and it does not scale — which is fine. Ten good entries per city beat a
thousand generated ones.

## 6. Your own pins

Not part of the pipeline. Created in the app, stored locally in SwiftData, merged into the map view
at read time by `TDMSpots`. They use ids of the form `local:{uuid}` and are never uploaded in v1.

---

## 7. Merge and dedupe

Two candidates are the same place when **both** hold:

- great-circle distance < 60 m (< 25 m for `kind: intersection`, which are genuinely dense), and
- normalised name similarity > 0.82 (Jaro-Winkler on casefolded, diacritic-stripped, suffix-stripped
  names), **or** one of them has no name.

On merge: keep the highest-priority `id` (`curated` > `wikidata` > `osm` > `commons`), union the
`sources` and `tags`, prefer a curated `name` and `note`, take the mean coordinate weighted toward
the curated or OSM position, and keep the maximum of each score factor.

Merging is order-dependent if done naively. Do it as single-link clustering over the candidate set,
then reduce each cluster once — that way the result does not depend on source order.

## 8. Scoring

```
raw = 0.45 · photoDensityNorm
    + 0.25 · notabilityNorm
    + 0.20 · featurePrior
    + 1.00 · curationBoost            (0 unless curated)

score = raw normalised to 0…1 across the city
```

- `photoDensityNorm` — `log1p(count) / log1p(p95_count)`, clamped to 1. Log because photo counts are
  wildly heavy-tailed; the 95th percentile rather than the max so one hyper-photographed landmark
  does not flatten everything else.
- `notabilityNorm` — `log1p(sitelinks) / log1p(100)`, clamped.
- `featurePrior` — a fixed table by `kind`, reflecting what tends to be good for street work:
  `market 0.9` · `plaza 0.85` · `transit 0.8` · `street 0.8` · `stairs 0.7` · `underpass 0.7` ·
  `intersection 0.7` · `bridge 0.65` · `waterfront 0.6` · `arcade 0.6` · `viewpoint 0.5` ·
  `park 0.45` · `landmark 0.4` · `other 0.2`.

`landmark` scores *low* on purpose. A monument with 4000 photos of the monument is not a street
photography spot; the photo-density term will already have over-rewarded it, and this pulls it back.

Every term writes a `scoreFactor` with human-readable `detail`. The UI shows those, never the number
alone — "137 geotagged photos nearby · marketplace · curated" tells you something; "0.87" does not.

## 9. Scheduling

A GitHub Actions workflow (`.github/workflows/bundles.yml`) runs monthly and on manual dispatch,
regenerates all cities, and opens a PR. Data refreshes therefore arrive as a **reviewable diff** —
you can see that a spot vanished because someone retagged it in OSM, rather than discovering it in
the field.

The workflow must not run on every push. These are volunteer-run APIs.
