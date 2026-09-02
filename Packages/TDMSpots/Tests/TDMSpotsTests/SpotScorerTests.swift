import Foundation
import Testing
import TDMCore
@testable import TDMSpots

@Suite("Scoring — SPOTFORGE §8")
struct SpotScorerTests {
    /// The four candidates of the worked example in `docs/SPOTFORGE.md` §8.
    static func workedExample() -> [SpotScoringInput] {
        func spot(_ id: String, _ kind: SpotKind, curated: Bool = false, refs: [String: String] = [:]) -> Spot {
            Spot(id: id, name: id, lat: 40.75, lon: -73.98, kind: kind, sources: [], score: 0, refs: refs, curated: curated)
        }

        return [
            SpotScoringInput(
                spot: spot("curated:us-nyc/fifth-42nd", .intersection, curated: true),
                photoCount: 58,
                curationBoost: 0.25,
                curationNote: "NYC canon"
            ),
            SpotScoringInput(
                spot: spot("osm:node/357555716", .plaza, refs: ["wikidata": "Q1163609"]),
                photoCount: 137,
                sitelinks: 34
            ),
            SpotScoringInput(spot: spot("osm:way/12345", .market), photoCount: 42),
            SpotScoringInput(
                spot: spot("osm:node/999", .landmark, refs: ["wikidata": "Q243"]),
                photoCount: 300,
                sitelinks: 60
            )
        ]
    }

    struct ExpectedRow: Sendable, CustomStringConvertible {
        let id: String
        let photoDensity: Double
        let notability: Double
        let featurePrior: Double
        let curation: Double?
        let score: Double

        var description: String { id }
    }

    /// The table in `docs/SPOTFORGE.md` §8, to six decimals. If this fails, the
    /// document and the code have diverged and one of them is the bug.
    static let expected: [ExpectedRow] = [
        ExpectedRow(id: "curated:us-nyc/fifth-42nd", photoDensity: 0.427150, notability: 0.000000, featurePrior: 0.186001, curation: 0.332144, score: 0.945295),
        ExpectedRow(id: "osm:node/357555716", photoDensity: 0.516164, notability: 0.255874, featurePrior: 0.225858, curation: nil, score: 0.997896),
        ExpectedRow(id: "osm:way/12345", photoDensity: 0.394012, notability: 0.000000, featurePrior: 0.239144, curation: nil, score: 0.633156),
        ExpectedRow(id: "osm:node/999", photoDensity: 0.597860, notability: 0.295854, featurePrior: 0.106286, curation: nil, score: 1.000000)
    ]

    @Test("Scoring reproduces the worked example", arguments: expected)
    func reproducesWorkedExample(row: ExpectedRow) throws {
        let scored = SpotScorer.score(Self.workedExample())
        let spot = try #require(scored.first { $0.id == row.id })

        func contribution(_ kind: ScoreFactorKind) -> Double? {
            spot.scoreFactors.first { $0.kind == kind }?.contribution
        }

        #expect(spot.score == row.score)
        #expect(contribution(.photoDensity) == row.photoDensity)
        #expect(contribution(.notability) == row.notability)
        #expect(contribution(.featurePrior) == row.featurePrior)
        #expect(contribution(.curation) == row.curation)
    }

    @Test("The published factors sum to the published score")
    func factorsSumToScore() {
        // At the six decimals the bundle publishes, not merely within some
        // tolerance: the scorer folds the rounding residual back into the
        // largest factor so the breakdown cannot contradict the badge.
        for spot in SpotScorer.score(Self.workedExample()) {
            let total = spot.scoreFactors.map(\.contribution).reduce(0, +)
            #expect((total * 1_000_000).rounded() / 1_000_000 == spot.score, "\(spot.id)")
        }
    }

    /// The UI shows these sentences, never the number alone.
    @Test("Every term emits a human-readable detail")
    func everyTermHasDetail() throws {
        let scored = SpotScorer.score(Self.workedExample())

        let curated = try #require(scored.first { $0.curated })
        #expect(curated.scoreFactors.map(\.kind) == [.photoDensity, .notability, .featurePrior, .curation])
        #expect(curated.scoreFactors.map(\.detail) == [
            "58 geotagged photos within 150 m",
            "not in Wikidata",
            "intersection",
            "curated: NYC canon"
        ])

        let plaza = try #require(scored.first { $0.id == "osm:node/357555716" })
        #expect(plaza.scoreFactors.first { $0.kind == .notability }?.detail == "Wikidata: Q1163609, 34 language editions")
        #expect(plaza.scoreFactors.allSatisfy { !$0.detail.isEmpty })
    }

    @Test("The 95th percentile is taken by nearest rank")
    func percentileByNearestRank() {
        #expect(SpotScorer.photoCountPercentile95([]) == 0)
        #expect(SpotScorer.photoCountPercentile95([7]) == 7)
        #expect(SpotScorer.photoCountPercentile95([42, 58, 137, 300]) == 300)
        // 100 values 1…100: rank ceil(95) = 95.
        #expect(SpotScorer.photoCountPercentile95(Array(1...100)) == 95)
        // Order must not matter.
        #expect(SpotScorer.photoCountPercentile95(Array((1...100).reversed())) == 95)
    }

    @Test("Photo density is log-compressed against the p95, and clamps above it")
    func photoDensityIsLogCompressed() {
        // Ten times the photos is nothing like ten times the term.
        let low = SpotScorer.photoDensityNorm(count: 30, reference: 300)
        let high = SpotScorer.photoDensityNorm(count: 300, reference: 300)
        #expect(abs(low - log1p(30) / log1p(300)) < 1e-12)
        #expect(high == 1)
        #expect(low > 0.5)

        // A spot above the 95th percentile does not get to exceed it.
        #expect(SpotScorer.photoDensityNorm(count: 4000, reference: 300) == 1)
        #expect(SpotScorer.photoDensityNorm(count: 0, reference: 300) == 0)
        #expect(SpotScorer.photoDensityNorm(count: 10, reference: 0) == 0)
    }

    @Test("Notability is log-compressed against 100 sitelinks")
    func notabilityIsLogCompressed() {
        #expect(SpotScorer.notabilityNorm(sitelinks: nil) == 0)
        #expect(SpotScorer.notabilityNorm(sitelinks: 0) == 0)
        #expect(abs(SpotScorer.notabilityNorm(sitelinks: 34) - log1p(34) / log1p(100)) < 1e-12)
        #expect(SpotScorer.notabilityNorm(sitelinks: 400) == 1)
    }

    /// A monument with 4000 photos of the monument is not a street photography
    /// spot, and the table is what pulls it back.
    @Test("The feature prior ranks street geometry above monuments")
    func featurePriorTable() {
        #expect(SpotScorer.featurePrior(for: .market) == 0.9)
        #expect(SpotScorer.featurePrior(for: .plaza) == 0.85)
        #expect(SpotScorer.featurePrior(for: .landmark) == 0.4)
        #expect(SpotScorer.featurePrior(for: .other) == 0.2)
        #expect(SpotScorer.featurePrior(for: .landmark) < SpotScorer.featurePrior(for: .street))
        #expect(SpotKind.allCases.allSatisfy { (0...1).contains(SpotScorer.featurePrior(for: $0)) })
    }

    @Test("Scores are normalised within the city, so the best spot is 1.0")
    func normalisedWithinTheCity() {
        let scored = SpotScorer.score(Self.workedExample())

        #expect(scored.map(\.score).max() == 1)
        #expect(scored.allSatisfy { (0...1).contains($0.score) })
    }

    /// Ranking is re-runnable: a city of one, or a city where nothing scores,
    /// must not divide by zero or produce a NaN that spreads into the UI.
    @Test("Degenerate cities do not produce NaNs")
    func degenerateCities() {
        #expect(SpotScorer.score([]).isEmpty)

        let barren = Spot(id: "osm:1", name: "", lat: 0, lon: 0, kind: .other, sources: [.osm], score: 0)
        let scored = SpotScorer.score([SpotScoringInput(spot: barren)])
        #expect(scored.count == 1)
        #expect(scored[0].score == 1)  // it is the best spot in its city, such as it is
        #expect(!scored[0].score.isNaN)
    }

    /// Pipeline arithmetic can produce a non-finite radius or boost; neither is
    /// worth trapping on during an import.
    @Test("Non-finite pipeline values do not trap or leak into the score")
    func toleratesNonFiniteInput() throws {
        var inputs = Self.workedExample()
        inputs[0].photoRadiusMetres = .infinity
        inputs[0].curationBoost = .nan

        let scored = SpotScorer.score(inputs)
        let spot = try #require(scored.first { $0.id == "curated:us-nyc/fifth-42nd" })

        #expect(spot.score.isFinite)
        #expect(spot.scoreFactors.allSatisfy { $0.contribution.isFinite })
        #expect(spot.scoreFactors.contains { $0.detail == "58 geotagged photos nearby" })
    }
}
