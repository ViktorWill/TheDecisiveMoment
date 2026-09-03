import Foundation
import TDMCore
import TDMSpots

/// Knobs the pipeline exposes. Defaults are the documented ones.
public struct PipelineOptions: Sendable {
    /// `docs/DATA-BUNDLES.md`, "Size budget": under 500 KB compressed.
    public var sizeBudgetBytes: Int
    /// How many of the top spots get representative Commons images. Each one is
    /// a request, so this is small on purpose.
    public var photoSpotLimit: Int
    public var photosPerSpot: Int
    /// Fetch representative images at all. Off for a fixture-driven build.
    public var fetchesPhotos: Bool
    public var mergeRules: MergeRules

    public init(
        sizeBudgetBytes: Int = 500 * 1024,
        photoSpotLimit: Int = 40,
        photosPerSpot: Int = 2,
        fetchesPhotos: Bool = true,
        mergeRules: MergeRules = .standard
    ) {
        self.sizeBudgetBytes = sizeBudgetBytes
        self.photoSpotLimit = photoSpotLimit
        self.photosPerSpot = photosPerSpot
        self.fetchesPhotos = fetchesPhotos
        self.mergeRules = mergeRules
    }
}

/// fetch → normalise → merge → score → trim → write.
///
/// The merge and the scoring are `TDMSpots.SpotMerger` and `TDMSpots.SpotScorer`
/// — the same code the app links — rather than a second implementation that
/// could drift from the one the client reasons about.
public struct Pipeline: Sendable {
    public let city: CityDefinition
    public let sources: [any SpotSource]
    /// Held separately as well as in `sources`: the density grid it accumulates
    /// is what the scorer's photo term reads.
    public let commons: CommonsSource?
    public let runner: RequestRunner?
    public var options: PipelineOptions
    /// Unconditional progress lines, to stderr by default — issue #17: a
    /// multi-hour run and a genuine hang were indistinguishable without this.
    public var progress: @Sendable (String) -> Void

    public init(
        city: CityDefinition,
        sources: [any SpotSource],
        commons: CommonsSource? = nil,
        runner: RequestRunner? = nil,
        options: PipelineOptions = PipelineOptions(),
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.city = city
        self.sources = sources
        self.commons = commons
        self.runner = runner
        self.options = options
        self.progress = progress
    }

    public struct Output: Sendable {
        public var city: City
        public var report: BuildReport
    }

    public func run(bundleVersion: Int, generatedAt: Date = Date()) async -> Output {
        var report = BuildReport(cityId: city.id)

        // 1 fetch, 2 normalise
        let fetchStarted = Date()
        var candidates: [Spot] = []
        var signals: [String: RawSpot] = [:]
        for source in sources {
            var tally = BuildReport.SourceTally(source: source.sourceKind, candidates: 0, failure: nil)
            for district in city.queryBoxes {
                let label = city.districts.count > 1 ? "\(source.sourceKind.rawValue) · \(district.name)" : source.sourceKind.rawValue
                progress("\(label): fetching")
                do {
                    // Commons reports its own sweep progress — a lattice
                    // sweep can be hundreds of requests, one source among
                    // several fetched per district.
                    let raws: [RawSpot] = if source.sourceKind == .commons, let commons {
                        try await commons.fetch(bbox: district.bbox, label: label, progress: progress)
                    } else {
                        try await source.fetch(bbox: district.bbox)
                    }
                    for raw in raws {
                        var raw = raw
                        if city.districts.count > 1, !raw.tags.contains(district.name.lowercased()) {
                            raw.tags.append(district.name.lowercased())
                        }
                        signals[raw.id] = raw
                        candidates.append(raw.normalised)
                        tally.candidates += 1
                    }
                    progress("\(label): \(raws.count) candidates")
                } catch {
                    tally.failure = String(describing: error)
                    progress("\(label): failed — \(error)")
                }
            }
            report.sources.append(tally)
        }
        report.candidateCount = candidates.count
        report.recordStage("fetch", since: fetchStarted)

        // 3 merge
        progress("merge: \(candidates.count) candidates")
        let mergeStarted = Date()
        let merged = SpotMerger.merge(candidates, rules: options.mergeRules)
        report.mergedCount = merged.count
        report.recordStage("merge", since: mergeStarted)

        // 4 score
        progress("score: \(merged.count) spots")
        let scoreStarted = Date()
        let grid = await commons?.densityGrid() ?? PhotoDensityGrid(referenceLatitude: city.center.latitude)
        report.photoCells = grid.counts.count
        report.photoTotal = grid.totalPhotos
        let scored = SpotScorer.score(merged.map { scoringInput(for: $0, grid: grid, signals: signals) })
        report.recordStage("score", since: scoreStarted)

        // 5 trim
        progress("trim")
        let trimStarted = Date()
        let (kept, floor) = trim(scored)
        report.droppedBySizeCap = scored.count - kept.count
        report.scoreFloor = floor
        report.recordStage("trim", since: trimStarted)

        // 6 write — the caller does the writing; the pipeline hands over the
        // city that will be written, photos and all.
        if options.fetchesPhotos { progress("photos: up to \(min(kept.count, options.photoSpotLimit)) spots") }
        let photosStarted = Date()
        var spots = kept
        if options.fetchesPhotos, let commons {
            spots = await attachPhotos(to: spots, using: commons)
        }
        report.spotCount = spots.count
        report.recordStage("photos", since: photosStarted)

        var built = City(
            cityId: city.id,
            name: city.name,
            country: city.country,
            bundleVersion: bundleVersion,
            generatedAt: generatedAt,
            generator: SpotForge.generator,
            bbox: city.bbox,
            attribution: Attribution(
                osm: "© OpenStreetMap contributors, ODbL 1.0",
                wikidata: "Wikidata, CC0 1.0",
                commons: "Wikimedia Commons — per-file licence in photo entries"
            ),
            scoreFloor: floor,
            spots: spots.sorted { $0.id < $1.id }
        )
        built.spots = built.spots.filter(\.isValid)

        if let runner {
            report.requestCount = await runner.requestCount
            report.cacheHitCount = await runner.cacheHitCount
        }
        return Output(city: built, report: report)
    }

    /// The raw signals the scorer needs, gathered from the candidates behind a
    /// merged spot. `refs` is the join: the merger unions it, so a merged spot
    /// still knows which Q-id and which curated entry it came from.
    func scoringInput(for spot: Spot, grid: PhotoDensityGrid, signals: [String: RawSpot]) -> SpotScoringInput {
        var sitelinks: Int?
        var boost = 0.0
        var curationNote: String?

        if let qid = spot.refs["wikidata"], let raw = signals["wikidata:\(qid)"] {
            sitelinks = raw.sitelinks
        }
        if let curatedId = spot.refs["curated"], let raw = signals["curated:\(curatedId)"] {
            boost = raw.curationBoost
            curationNote = raw.curationNote
        }

        return SpotScoringInput(
            spot: spot,
            photoCount: grid.count(around: spot.coordinate),
            photoRadiusMetres: grid.neighbourhoodRadiusMetres,
            sitelinks: sitelinks,
            curationBoost: boost,
            curationNote: curationNote
        )
    }

    /// Stage 5. Tighten the score floor rather than truncating arbitrarily, and
    /// never drop a curated entry: a hand-written spot that scored low is still
    /// the spot someone chose to write about.
    func trim(_ spots: [Spot]) -> (kept: [Spot], floor: Double?) {
        guard measure(spots) > options.sizeBudgetBytes else { return (spots, nil) }

        let ranked = spots.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        let curated = ranked.filter(\.curated)
        var generated = ranked.filter { !$0.curated }

        // Halve the generated tail until it fits, then walk back up: the
        // measurement is a gzip of the whole city, so a linear scan would be
        // thousands of compressions.
        var low = 0
        var high = generated.count
        while low < high {
            let middle = (low + high + 1) / 2
            if measure(curated + generated.prefix(middle)) <= options.sizeBudgetBytes {
                low = middle
            } else {
                high = middle - 1
            }
        }
        generated = Array(generated.prefix(low))

        let kept = curated + generated
        let floor = generated.last?.score ?? kept.map(\.score).min()
        return (kept, floor)
    }

    /// Compressed size, measured exactly the way the bundle is written.
    func measure(_ spots: [Spot]) -> Int {
        let probe = City(
            cityId: city.id,
            name: city.name,
            country: city.country,
            bundleVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 0),
            generator: SpotForge.generator,
            bbox: city.bbox,
            attribution: Attribution(),
            spots: spots
        )
        guard let json = try? BundleCoding.encoder().encode(probe) else { return .max }
        return GzipWriter.compress(json).count
    }

    /// Representative images for the top spots. A failure here costs a picture,
    /// not a bundle, so it is swallowed per spot rather than failing the build.
    func attachPhotos(to spots: [Spot], using commons: CommonsSource) async -> [Spot] {
        let top = spots
            .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
            .prefix(options.photoSpotLimit)
            .map(\.id)
        let wanted = Set(top)

        var result: [Spot] = []
        for spot in spots {
            guard wanted.contains(spot.id), spot.photos.isEmpty else {
                result.append(spot)
                continue
            }
            var spot = spot
            if let photos = try? await commons.photos(near: spot.coordinate, limit: options.photosPerSpot) {
                spot.photos = photos
            }
            result.append(spot)
        }
        return result
    }
}
