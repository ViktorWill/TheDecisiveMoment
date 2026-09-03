import Foundation
import Testing
import TDMCore
@testable import TDMSpots

@Suite("Annotations, clustering and the 300 cap — SPEC-map.md")
struct SpotClustererTests {
    static let region = BoundingBox(minLat: 40.70, minLon: -74.02, maxLat: 40.78, maxLon: -73.94)

    static func spot(
        id: String,
        lat: Double = 40.73,
        lon: Double = -73.99,
        score: Double = 0.5,
        curated: Bool = false
    ) -> Spot {
        Spot(
            id: id, name: id, lat: lat, lon: lon, kind: .street, sources: [.osm],
            score: score, curated: curated
        )
    }

    @Test("A tight region draws every spot individually")
    func individualBelowTheClusteringSpan() {
        // ~440 m across, well under the 2 km clustering span.
        let block = BoundingBox(minLat: 40.730, minLon: -73.990, maxLat: 40.734, maxLon: -73.9848)
        let spots = (0..<5).map { Self.spot(id: "osm:\($0)", lat: 40.731 + Double($0) / 10_000) }

        let annotations = SpotClusterer.annotations(for: spots, in: block)

        #expect(SpotClusterer.visibleSpanMetres(of: block) < SpotClusterer.clusteringSpanMetres)
        #expect(annotations.clusters.count == 5)
        #expect(annotations.clusters.allSatisfy { $0.isSingle })
        #expect(!annotations.isLimited)
    }

    @Test("A wide region merges neighbours into bubbles carrying their best member")
    func clustersAboveTheSpan() {
        let spots = [
            Self.spot(id: "osm:a", lat: 40.7300, lon: -73.9900, score: 0.4),
            Self.spot(id: "osm:b", lat: 40.7301, lon: -73.9901, score: 0.8),
            Self.spot(id: "osm:far", lat: 40.7700, lon: -73.9500, score: 0.6)
        ]

        let annotations = SpotClusterer.annotations(for: spots, in: Self.region)

        #expect(SpotClusterer.visibleSpanMetres(of: Self.region) > SpotClusterer.clusteringSpanMetres)
        #expect(annotations.clusters.count == 2)
        let bubble = annotations.clusters.first { !$0.isSingle }
        #expect(bubble?.count == 2)
        #expect(bubble?.representative.id == "osm:b")
    }

    @Test("Over the cap the floor rises and says so")
    func capRaisesTheFloor() {
        let spots = (0..<400).map { index in
            Self.spot(id: String(format: "osm:%03d", index), score: Double(index) / 400)
        }

        let annotations = SpotClusterer.annotations(for: spots, in: Self.region)

        #expect(annotations.matchingSpotCount == 400)
        #expect(annotations.isLimited)
        // The 300th best of 400 evenly spread scores sits at 0.25 of the way up.
        #expect(abs(annotations.effectiveMinimumScore - 0.25) < 1e-9)
        #expect(annotations.clusters.reduce(0) { $0 + $1.count } == 300)
    }

    @Test("Under the cap the user's own floor is what is reported")
    func floorIsUntouchedUnderTheCap() {
        let annotations = SpotClusterer.annotations(
            for: [Self.spot(id: "osm:1")],
            in: Self.region,
            requestedMinimumScore: 0.3
        )

        #expect(!annotations.isLimited)
        #expect(annotations.effectiveMinimumScore == 0.3)
    }

    @Test("Curated spots draw last, so they draw on top")
    func curatedDrawsOnTop() {
        let block = BoundingBox(minLat: 40.730, minLon: -73.990, maxLat: 40.734, maxLon: -73.9848)
        let spots = [
            Self.spot(id: "curated:1", lat: 40.7310, score: 0.2, curated: true),
            Self.spot(id: "osm:1", lat: 40.7320, score: 0.9),
            Self.spot(id: "osm:2", lat: 40.7330, score: 0.4)
        ]

        let annotations = SpotClusterer.annotations(for: spots, in: block)

        #expect(annotations.clusters.map(\.id) == ["osm:2", "osm:1", "curated:1"])
    }

    @Test("The same region twice gives the same annotation ids")
    func clusteringIsStable() {
        let spots: [Spot] = (0..<40).map { index in
            Self.spot(
                id: "osm:\(index)",
                lat: 40.71 + Double(index) / 1_000,
                lon: -74.0 + Double(index) / 900
            )
        }

        let first = SpotClusterer.annotations(for: spots, in: Self.region)
        let second = SpotClusterer.annotations(for: spots.reversed(), in: Self.region)

        #expect(first.clusters.map(\.id) == second.clusters.map(\.id))
    }
}
