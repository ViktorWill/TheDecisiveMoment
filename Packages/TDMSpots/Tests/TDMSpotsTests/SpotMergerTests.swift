import Foundation
import Testing
import TDMCore
@testable import TDMSpots

/// A synthetic cluster around Washington Square, in the shape the pipeline
/// produces: the same place described by three sources that agree on neither
/// the name nor the exact position.
enum MergeSample {
    static func spot(
        id: String,
        name: String,
        lat: Double,
        lon: Double,
        kind: SpotKind = .plaza,
        sources: [SpotSource],
        tags: [String] = [],
        openness: Openness = .open,
        streetBearing: Double? = nil,
        note: String? = nil,
        bestHours: [Int]? = nil,
        refs: [String: String] = [:],
        photos: [SpotPhoto] = [],
        score: Double = 0,
        scoreFactors: [ScoreFactor] = [],
        curated: Bool = false
    ) -> Spot {
        Spot(
            id: id, name: name, lat: lat, lon: lon, kind: kind, sources: sources,
            score: score, scoreFactors: scoreFactors, tags: tags, bestHours: bestHours,
            streetBearing: streetBearing, openness: openness, note: note, refs: refs,
            photos: photos, curated: curated
        )
    }

    static let osm = spot(
        id: "osm:node/357555716",
        name: "Washington Square Park",
        lat: 40.73096,
        lon: -73.99725,
        sources: [.osm],
        tags: ["chess", "students"],
        openness: .canyon,
        streetBearing: 92,
        refs: ["osm": "node/357555716"],
        score: 0.4,
        scoreFactors: [ScoreFactor(kind: .photoDensity, contribution: 0.30, detail: "80 geotagged photos within 150 m")]
    )

    static let wikidata = spot(
        id: "wikidata:Q1163609",
        name: "Washington Square",
        lat: 40.73101,
        lon: -73.99719,
        kind: .other,
        sources: [.wikidata],
        tags: ["arch"],
        refs: ["wikidata": "Q1163609"],
        score: 0.5,
        scoreFactors: [ScoreFactor(kind: .notability, contribution: 0.22, detail: "Wikidata: Q1163609, 34 language editions")]
    )

    static let commons = spot(
        id: "commons:File:Washington_Square_Arch.jpg",
        name: "",
        lat: 40.73088,
        lon: -73.99740,
        kind: .other,
        sources: [.commons],
        photos: [
            SpotPhoto(
                thumbURL: "https://upload.wikimedia.org/thumb.jpg",
                pageURL: "https://commons.wikimedia.org/wiki/File:Washington_Square_Arch.jpg",
                author: "Jane Example",
                license: "CC BY-SA 4.0"
            )
        ],
        score: 0.2,
        scoreFactors: [ScoreFactor(kind: .photoDensity, contribution: 0.41, detail: "137 geotagged photos within 150 m")]
    )

    static let curated = spot(
        id: "curated:us-nyc/washington-square",
        name: "Washington Square Arch",
        lat: 40.73093,
        lon: -73.99730,
        sources: [.curated],
        tags: ["crowds", "performers"],
        openness: .open,
        streetBearing: 15,
        note: "Arch frames northward up Fifth Avenue.",
        bestHours: [7, 8],
        score: 0.9,
        scoreFactors: [ScoreFactor(kind: .curation, contribution: 0.25, detail: "curated: NYC canon")],
        curated: true
    )

    /// A different place, 400 m away, that must not join the cluster.
    static let elsewhere = spot(
        id: "osm:node/1",
        name: "Astor Place",
        lat: 40.73000,
        lon: -74.00200,
        sources: [.osm]
    )

    static let all = [osm, wikidata, commons, curated, elsewhere]
}

@Suite("Merge and dedupe — SPOTFORGE §7")
struct SpotMergerTests {
    /// The property the whole clustering approach exists for: sources are
    /// fetched concurrently and arrive in whatever order they finish in, and a
    /// bundle must not change because Overpass was slow that morning.
    @Test("Merging the same inputs in a shuffled order gives identical output", arguments: 0..<40)
    func mergeIsOrderIndependent(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed))
        let shuffled = MergeSample.all.shuffled(using: &generator)

        #expect(SpotMerger.merge(shuffled) == SpotMerger.merge(MergeSample.all))
    }

    @Test("A cluster collapses to one spot and leaves distant places alone")
    func clusterCollapses() {
        let merged = SpotMerger.merge(MergeSample.all)

        #expect(merged.count == 2)
        #expect(merged.contains { $0.id == "osm:node/1" })
    }

    @Test("The reduction follows the §7 table")
    func reductionRules() throws {
        let merged = SpotMerger.merge(MergeSample.all)
        let spot = try #require(merged.first { $0.id != "osm:node/1" })

        // Highest-priority id and a curated name, note and openness.
        #expect(spot.id == "curated:us-nyc/washington-square")
        #expect(spot.name == "Washington Square Arch")
        #expect(spot.note == "Arch frames northward up Fifth Avenue.")
        #expect(spot.openness == .open)
        #expect(spot.streetBearing == 15)
        #expect(spot.curated)

        // Unions.
        #expect(spot.sources == [.osm, .wikidata, .commons, .curated])
        #expect(spot.tags == ["arch", "chess", "crowds", "performers", "students"])
        #expect(spot.bestHours == [7, 8])
        #expect(spot.refs == ["osm": "node/357555716", "wikidata": "Q1163609"])
        #expect(spot.photos.count == 1)

        // A specific kind beats `other`.
        #expect(spot.kind == .plaza)

        // The maximum of each factor kind, and the best score in the cluster.
        #expect(spot.scoreFactors.count == 3)
        #expect(spot.scoreFactors.first { $0.kind == .photoDensity }?.contribution == 0.41)
        #expect(spot.score == 0.9)

        // Weighted mean, pulled toward the curated and OSM positions.
        // (3·curated + 2·osm + wikidata + commons) / 7
        #expect(abs(spot.lat - 40.7309429) < 1e-7)
        #expect(abs(spot.lon - (-73.9972843)) < 1e-7)
    }

    @Test("A nameless candidate merges on distance alone")
    func namelessCandidateMerges() {
        #expect(SpotMerger.isSamePlace(MergeSample.osm, MergeSample.commons))
    }

    /// Two corners of the same junction are different places to stand, so
    /// intersections get the tighter radius.
    @Test("Intersections use the 25 m radius, not 60 m")
    func intersectionsAreTighter() {
        let north = MergeSample.spot(
            id: "osm:node/10", name: "Fifth & 42nd", lat: 40.75350, lon: -73.98130,
            kind: .intersection, sources: [.osm]
        )
        // ~40 m north: inside the 60 m rule, outside the intersection rule.
        let south = MergeSample.spot(
            id: "osm:node/11", name: "Fifth & 42nd", lat: 40.75314, lon: -73.98130,
            kind: .intersection, sources: [.osm]
        )

        #expect(north.coordinate.distance(to: south.coordinate) > 25)
        #expect(north.coordinate.distance(to: south.coordinate) < 60)
        #expect(!SpotMerger.isSamePlace(north, south))
        #expect(SpotMerger.merge([north, south]).count == 2)
    }

    /// Single-link means A–B and B–C put A and C together even though A and C
    /// alone would not have matched. That is the intended behaviour: it is what
    /// makes the result independent of which pair was compared first.
    @Test("Single-link clustering closes a chain transitively")
    func chainsCloseTransitively() {
        let a = MergeSample.spot(id: "osm:a", name: "", lat: 40.73000, lon: -73.99000, sources: [.osm])
        let b = MergeSample.spot(id: "osm:b", name: "", lat: 40.73045, lon: -73.99000, sources: [.osm])
        let c = MergeSample.spot(id: "osm:c", name: "", lat: 40.73090, lon: -73.99000, sources: [.osm])

        #expect(a.coordinate.distance(to: c.coordinate) > 60)
        #expect(SpotMerger.merge([a, b, c]).count == 1)
        #expect(SpotMerger.merge([c, a, b]).count == 1)
    }

    @Test("Names normalise past the generic tail")
    func nameNormalisation() {
        #expect(SpotName.normalized("Washington Square Park") == "washington")
        #expect(SpotName.normalized("The Marché aux Puces") == "marche aux puces")
        #expect(SpotName.normalized("Park") == "park")
        #expect(SpotName.similarity("Washington Square Park", "Washington Sq.") > 0.82)
        #expect(SpotName.similarity("Astor Place", "Washington Square") < 0.82)
    }
}

/// Deterministic shuffles, so a failing seed can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
