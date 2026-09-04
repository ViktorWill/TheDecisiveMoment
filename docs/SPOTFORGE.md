# spotforge — the bundle pipeline

A Swift command-line executable at `Tools/spotforge`. It runs at build time — never on a phone —
and turns four sources into the city bundles described in [DATA-BUNDLES.md](DATA-BUNDLES.md).

There is no `Package.swift` at the repo root — this is a multi-package layout, and `spotforge` is
its own package. Run it with `--package-path` from wherever you are, rather than `cd`-ing into
`Tools/spotforge`; the working directory that `--out` and `--cities` resolve against stays wherever
you invoked `swift run` from, which for these examples is the repo root:

```sh
swift run --package-path Tools/spotforge spotforge build --city us-nyc --out bundles/v1
swift run --package-path Tools/spotforge spotforge build --all --out bundles/v1
swift run --package-path Tools/spotforge spotforge validate bundles/v1
```

It links `TDMCore`, so it writes the same `Spot` type the app decodes. The schema cannot drift.

> ### Endpoint check, 2026-09
>
> The queries below were originally written from documentation and never executed. They have since
> been checked against the current published API references for Overpass QL, the Wikidata Query
> Service and the MediaWiki `geosearch` and `imageinfo` modules, and the sections below were
> corrected where the documentation and the original text disagreed — see §2 (`out` takes one
> geometry mode, so features need two passes), §4 (`gsradius` bounds and the sampling lattice).
>
> They have **not** been run against the live services: the sandbox this was implemented in resolves
> no DNS for `overpass-api.de`, `query.wikidata.org` or `commons.wikimedia.org`, and pretending
> otherwise would be worse than saying so. The first real run is the first `spotforge build` without
> `--fixtures`; if a response shape has drifted since, fix this document in the same change.

## Stages

```
  ┌─────────┐   ┌─────────┐   ┌────────┐   ┌───────┐   ┌────────┐   ┌───────┐   ┌────────┐
  │ 1 fetch │──►│ 2 norm. │──►│ 3 merge│──►│4 score│──►│5 photos│──►│6 trim │──►│7 write │
  └─────────┘   └─────────┘   └────────┘   └───────┘   └────────┘   └───────┘   └────────┘
   per source    → Spot        dedupe       0…1 norm.   top spots    size cap    gz + sha
```

The photo pass comes **before** the trim, not after it. Photo entries are bytes — `thumbURL`,
`pageURL`, `author`, `license` — so a trim that measured a city without them measured a city that
was never written, and the bundle went over budget unnoticed. The trim's probe is now built by the
same code that builds the artefact, down to the `scoreFloor`, the attribution block and the
`generatedAt` instant, so the size it binary-searches on is the size on disk. Photos are selected by
score rank, which is known after stage 4, so the reorder costs no extra requests; it does mean a few
photos are fetched for spots the trim then drops.

The size of the bundle actually written is checked against the budget after the write, and a bundle
over budget is a warning like any other — so `--strict` fails the build. That can still happen
legitimately: curated entries are never dropped, so a budget smaller than the curated canon is
unreachable and says so rather than silently passing.

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
)->.spots;
.spots out center tags;
.spots out ids geom;
```

`out center` gives a single representative coordinate for ways, which is what the map needs — but an
`out` statement takes **one** geometry mode, so `out center geom` is not a thing. The set is stored
as `.spots` and printed twice: once for the centre and the tags, once for the node geometry the
street bearing is derived from. Records are rejoined by `type` and `id`; a way that appears only in
the first pass simply has no bearing.

The building heights the `canyon` reading needs are a second query, because a building is not a spot
and must not end up in the candidate set:

```
[out:json][timeout:180];
(
  way ["building"]["building:levels"]({{bbox}});
  way ["building"]["height"]({{bbox}});
);
out center tags;
```

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
- **`openness`** — `covered` when `tunnel=yes`, `covered=yes` or `building=arcade`; `canyon` when at
  least two buildings sit within 30 m and their mean height exceeds 25 m; `open` otherwise. Heights
  come from `height` where it is tagged and from `building:levels` × 3.1 m where it is not. Be
  conservative — a wrong `canyon` costs the user 3.5 stops, so a point with one tall neighbour and
  nothing else stays `open`.

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
looks broken. `gsradius` takes 10–10 000 m and `gslimit` caps at 500.

Rather than one query per candidate spot — which would be thousands of requests — sweep the city and
accumulate counts into a grid of **250 m cells**, then read each candidate's density from its cell
plus its eight neighbours. One pass, bounded cost, and the resulting grid is also what draws the
heatmap layer.

The sweep samples on a **500 m lattice with `gsradius=500`**, which is not the same number as the
cell size: circles of radius 500 m centred every 500 m overlap everywhere, since the furthest a
point can be from the nearest sample is 354 m. A file returned by two overlapping samples is counted
once, by page id. A cell holding 25 files or more becomes a candidate in its own right — somewhere
people photograph that no other source names — with the id `commons:cell/{lat}/{lon}`.

A bbox large enough to need more than 20 000 samples fails the build rather than running for a day
against a volunteer service; that is what districts are for.

Commons `geosearch` is a separate service from Overpass with its own limits, so the sweep does not
have to inherit Overpass's one-at-a-time rule: `RequestRunner` gives the `commons` namespace a small
concurrency (a few requests in flight, still on a conservative interval) while Overpass and Wikidata
stay strictly serial. See §9.

For the top-scoring spots, fetch representative images with `prop=imageinfo` and
`iiprop=url|extmetadata` to get `thumbURL`, `pageURL`, author and licence. **Store the licence.** A
photo without attribution does not go in the bundle.

## 5. Curated canon

Hand-written YAML at `data/curated/{cityId}.yml`. Small, slow-growing, and the reason the app reads
like it was made by someone who shoots.

```yaml
- name: Fifth Avenue & 42nd Street
  slug: fifth-avenue-42nd
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

The id is `curated:{cityId}/{slug}`. `slug` is optional — it is derived from the name when it is
absent — but writing it down pins the id, so renaming an entry does not silently break a user's pin.
Two entries that reduce to the same slug fail the build.

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

On merge: keep the highest-priority `id` (`local` > `curated` > `wikidata` > `osm` > `commons`),
union the `sources` and `tags`, prefer a curated `name` and `note`, take the mean coordinate
weighted toward the curated or OSM position, and keep the maximum of each score factor.

Merging is order-dependent if done naively. Do it as single-link clustering over the candidate set,
then reduce each cluster once — that way the result does not depend on source order.

Comparing every candidate against every other is quadratic and does not scale past a few boroughs of
OSM features. Candidates are bucketed into a grid of cells sized at 60 m (the larger of the two
distance thresholds above) and only compared within the 3×3 block of cells around each one, so the
tighter 25 m intersection case is still caught. A candidate near a cell edge is still compared
against its neighbours in the adjacent cells, which is what keeps the result independent of input
order even with bucketing.

### Name normalisation

Before comparing, names are casefolded, diacritic- and width-folded, stripped of everything that is
not a letter or a digit, and then stripped of trailing **generic words**, repeatedly:

`square` · `sq` · `plaza` · `place` · `park` · `gardens` · `garden` · `market` · `marketplace` ·
`station` · `bridge` · `steps` · `stairs` · `street` · `st` · `avenue` · `ave` · `road` · `rd` ·
`lane` · `boulevard` · `blvd` · `the`

They name the *kind* of place, which the `kind` field already carries, so keeping them only
manufactures agreement. "Washington Square Park" and "Washington Square" both reduce to
`washington`. A leading `the` goes too. The last token is never stripped, so a name that is nothing
but a generic word survives as itself.

### Reducing a cluster

Every choice below is a total order over the members — sorted by source priority, then by `id`, and
where two records share an `id` by name, latitude, longitude and the remaining reduced fields — so
the reduction is a function of the *set*, not of the order the sources returned.

| Field | Rule |
|---|---|
| `id`, `kind` | Highest-priority member. A curated `kind` wins; `other` loses to any specific kind. |
| `sources`, `tags` | Union. `tags` sorted, so a rebuild does not diff on ordering. |
| `name`, `note` | Curated first, then the highest-priority member that has one at all. |
| `lat`, `lon` | Weighted mean. Weights: `local` and `curated` 3, `osm` 2, `wikidata` and `commons` 1 — a curated position is where a person stood, a Commons point is wherever the camera was, which may be a street away. |
| `openness` | Curated wins. Otherwise the **most open** reading of the members: a wrong `canyon` costs the user 3.5 stops. |
| `streetBearing` | Curated first, else the highest-priority member's. Bearings are circular and do not average — a mean of 350° and 10° points across the street. |
| `bestHours` | Union, sorted. `null` when no member has any. |
| `refs` | Union; the highest-priority member wins a key it defines. |
| `photos` | Union, deduplicated by `pageURL`, highest-priority member's first. |
| `scoreFactors` | The maximum contribution per factor kind. |
| `curated` | True when any member is. |

`score` and `scoreFactors` are recomputed by the scoring pass anyway; keeping the maxima here means
a merged set is still meaningfully ranked if it is inspected between the two stages.

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

### The two things "normalised" has to pin down

- **`p95_count`** is the 95th percentile by *nearest rank*: sort the city's counts ascending and take
  element `ceil(0.95 · n) − 1`. No interpolation, so the reference is always a count a real spot
  actually has. Below about twenty spots this is simply the maximum, which is fine — a city that
  small has no tail to be robust against.
- **`score = raw / max(raw)` across the city**, clamped to `0…1`. Dividing rather than min-maxing
  keeps zero meaning "nothing recommends this place"; the best spot in every city is 1.0, which is
  what "normalised within the city" is for.

The same factor is applied to each term, so the published `scoreFactors` are the terms' shares
*after* normalisation and **sum to `score`**. That is what lets the detail sheet show a breakdown
that does not contradict the number next to it. Contributions and scores are rounded to six
decimals so a regenerated bundle does not diff on floating-point noise, and the rounding residual —
including anything the `0…1` clamp removes — is folded into the largest factor so the identity
survives the rounding.

### Worked example

Four candidates, of which one is curated with `score_boost: 0.25`. Photo counts 58, 137, 42 and 300,
so `p95_count = 300`. Derived by running `SpotScorer` over these inputs — the same numbers are
asserted in `Packages/TDMSpots/Tests/TDMSpotsTests/SpotScorerTests.swift`, so this table and the
code cannot drift apart.

| Spot | kind | photos | sitelinks | boost | photoDensity | notability | featurePrior | curation | **score** |
|---|---|---|---|---|---|---|---|---|---|
| `curated:us-nyc/fifth-42nd` | intersection | 58 | — | 0.25 | 0.427150 | 0.000000 | 0.186001 | 0.332144 | **0.945295** |
| `osm:node/357555716` | plaza | 137 | 34 | — | 0.516164 | 0.255874 | 0.225858 | — | **0.997896** |
| `osm:way/12345` | market | 42 | — | — | 0.394012 | 0.000000 | 0.239144 | — | **0.633156** |
| `osm:node/999` | landmark | 300 | 60 | — | 0.597860 | 0.295854 | 0.106286 | — | **1.000000** |

Reading the first row: `photoDensityNorm = log1p(58)/log1p(300) = 0.714467`, times the 0.45 weight
gives `0.321510`; `featurePrior = 0.7` for an intersection, times 0.20 gives `0.14`; the curation
boost of `0.25` enters at weight 1.00. Raw total `0.711510`. The city maximum is the landmark's
`0.752686`, and `0.711510 / 0.752686 = 0.945295`, which is also what the row's four published
factors sum to.

The landmark still comes out on top here, and that is the honest behaviour of the model: the prior
narrows a seven-fold photo-count advantage, it does not reverse one. What pulls a working street
corner above a monument is a curated entry, which is exactly the trade the curated file exists to
make.

## 9. Scheduling

A GitHub Actions workflow (`.github/workflows/bundles.yml`) runs monthly and on manual dispatch,
regenerates all cities, and opens a PR. Data refreshes therefore arrive as a **reviewable diff** —
you can see that a spot vanished because someone retagged it in OSM, rather than discovering it in
the field.

The workflow must not run on every push. These are volunteer-run APIs. It builds and validates with
`-c release`; a five-borough `us-nyc` run in debug mode is slow enough to risk the Actions 6-hour cap.

`RequestRunner` enforces politeness per source rather than with one shared queue: Overpass and
Wikidata each get a strictly serial `HostPolicy` (one request at a time, a minimum interval between
them), matching their usage policies exactly. Commons `geosearch` gets its own `HostPolicy` with a
small concurrency, since it is a different service with different limits — see §4.

`spotforge` prints progress to stderr as it runs, unconditionally: which source and district is
being swept, a periodic counter (including how many responses were served from cache), each pipeline
stage as it starts, and per-stage elapsed time in the final `--report`. A build that is merely slow
and one that has hung are otherwise indistinguishable from the outside.

---

## 10. The command line

```
spotforge build --city <id> [--city <id>…] | --all [options]
spotforge validate [<directory>]
```

Invoked as `swift run --package-path Tools/spotforge spotforge <subcommand> …` from wherever you
want `--out` and `--cities` to resolve against — see the top of this document. There is no root
`Package.swift`, so a bare `swift run spotforge …` fails with *"Could not find Package.swift"*
unless you have separately `cd`'d into `Tools/spotforge`, which then resolves `--out bundles/v1`
against the wrong directory.

| Option | Meaning |
|---|---|
| `--out <dir>` | Where bundles are written. Default `bundles/v1`. |
| `--cities <path>` | City declarations. Default `data/cities.yml`. |
| `--curated <dir>` | Curated canon files. Default `data/curated`. |
| `--cache <dir>` | Response cache, keyed by query hash. Default `.cache`. |
| `--fixtures <dir>` | Build from recorded responses and touch no network. |
| `--report` | Print the per-source summary. |
| `--strict` | Exit non-zero when a source returned nothing or failed, or the bundle missed its size budget. |
| `--no-photos` | Skip the representative-image pass. |

`validate` re-reads `index.json`, decompresses every bundle, re-decodes it with the same
`TDMSpots.BundleDecoder` the app uses, and checks the SHA-256 over the decompressed JSON. It is the
last gate before a bundle is published, and it exits non-zero on the first thing that does not
add up.

`--fixtures` is how the tests — and anyone without network access — exercise the whole pipeline. The
recorded responses live in `Tools/spotforge/Tests/Fixtures/`, named `{label}-{cacheKey}.json`, where
the cache key is the same hash the disk cache uses. A request with no recording fails with
`HTTPError.offline` rather than falling back to the network, so a test can never quietly reach a
volunteer service. `Tools/spotforge/Tests/Fixtures/README.md` explains how to re-record one.
