# Recorded responses

Every file here is one recorded HTTP response, trimmed to what the pipeline
reads. The test suite and `spotforge build --fixtures` serve them through
`RecordedTransport`, so **no test in this package touches the network** — these
are volunteer-run services and CI is not allowed near them.

The hexadecimal tail of each name is the request's cache key: the SHA-256 over
the method, URL, headers and body, which is the same key the `.cache/` directory
uses. `RecordedTransport` matches on that tail, so the readable prefix is free
to say what the file is.

| File | Request |
|---|---|
| `overpass-features-…` | The §2 feature query over the fixture bbox, both `out` passes. |
| `overpass-buildings-…` | The `building:levels` query the `canyon` reading uses. |
| `wikidata-…` | The §3 SPARQL query, SPARQL 1.1 JSON results. |
| `commons-geosearch-…` | One `list=geosearch&gsnamespace=6` sample. |
| `commons-imageinfo-…` | `generator=geosearch&prop=imageinfo`, for representative photos. |
| `cities.yml` | A fixture city: 300 m around Washington Square, one Commons sample. |
| `curated/us-nyc.yml` | Two curated entries inside that bbox. |

To re-record after changing a query, run the build against the live services
once with `--cache .cache`, then copy the response out of `.cache/{source}/` —
the file name there is already the cache key.
