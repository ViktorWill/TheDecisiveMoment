import Foundation
import Testing
import TDMCore
@testable import TDMSpots

@Suite("Filtering and search — SPEC-map.md")
struct SpotFilterTests {
    static func spot(
        id: String,
        name: String,
        lat: Double = 40.75,
        lon: Double = -73.98,
        kind: SpotKind = .street,
        sources: [SpotSource] = [.osm],
        openness: Openness = .open,
        tags: [String] = [],
        score: Double = 0.5,
        curated: Bool = false
    ) -> Spot {
        Spot(
            id: id, name: name, lat: lat, lon: lon, kind: kind, sources: sources,
            score: score, tags: tags, openness: openness, curated: curated
        )
    }

    static let city: [Spot] = [
        spot(id: "osm:1", name: "Marché aux Puces", kind: .market, openness: .open, tags: ["crowds", "flea"], score: 0.9),
        spot(id: "osm:2", name: "Chinatown Arcade", kind: .arcade, openness: .covered, tags: ["shelter"], score: 0.6),
        spot(id: "curated:3", name: "Fifth & 42nd", kind: .intersection, sources: [.curated, .osm], openness: .canyon, tags: ["midtown"], score: 0.2, curated: true),
        spot(id: "local:4", name: "My corner", lat: 40.90, lon: -73.90, kind: .street, sources: [.local], tags: ["quiet"], score: 0.4),
        spot(id: "osm:5", name: "Brooklyn Bridge walkway", lat: 40.70, lon: -73.99, kind: .bridge, tags: ["tourists"], score: 0.7)
    ]

    @Test("An empty query returns the city, best first")
    func emptyQueryReturnsEverything() {
        let result = SpotFilter.apply(SpotQuery(), to: Self.city)

        #expect(result.count == Self.city.count)
        #expect(result.map(\.id) == ["osm:1", "osm:5", "osm:2", "local:4", "curated:3"])
    }

    @Test("A bounding box is the map's visible rectangle, nothing more")
    func boundingBoxFilters() {
        let manhattan = BoundingBox(minLat: 40.698, minLon: -74.020, maxLat: 40.880, maxLon: -73.907)
        let result = SpotFilter.apply(SpotQuery(boundingBox: manhattan), to: Self.city)

        #expect(!result.contains { $0.id == "local:4" })
        #expect(result.count == 4)
    }

    @Test("Kind and openness pills are unions within, intersections across")
    func kindAndOpennessFilter() {
        let byKind = SpotFilter.apply(SpotQuery(kinds: [.market, .bridge]), to: Self.city)
        #expect(byKind.map(\.id) == ["osm:1", "osm:5"])

        let byOpenness = SpotFilter.apply(SpotQuery(openness: [.covered, .canyon]), to: Self.city)
        #expect(Set(byOpenness.map(\.id)) == ["osm:2", "curated:3"])

        let both = SpotFilter.apply(SpotQuery(kinds: [.market], openness: [.covered]), to: Self.city)
        #expect(both.isEmpty)
    }

    @Test("Source filters cover curated only and my pins")
    func sourceFilter() {
        #expect(SpotFilter.apply(SpotQuery(sources: [.curated]), to: Self.city).map(\.id) == ["curated:3"])
        #expect(SpotFilter.apply(SpotQuery(sources: [.local]), to: Self.city).map(\.id) == ["local:4"])
        #expect(SpotFilter.apply(SpotQuery(sources: [.osm]), to: Self.city).count == 4)
    }

    @Test("The score floor drops the weak, and curation can override it")
    func scoreFloor() {
        let floored = SpotFilter.apply(SpotQuery(minimumScore: 0.5), to: Self.city)
        #expect(floored.map(\.id) == ["osm:1", "osm:5", "osm:2"])

        let keepingCurated = SpotFilter.apply(
            SpotQuery(minimumScore: 0.5, alwaysIncludeCurated: true),
            to: Self.city
        )
        #expect(keepingCurated.contains { $0.id == "curated:3" })
    }

    /// Offline, no network, and forgiving about accents — typing "marche" on a
    /// phone keyboard in the street has to find "Marché".
    @Test("Search is a substring match over name and tags")
    func searchMatchesNameAndTags() {
        #expect(SpotFilter.apply(SpotQuery(searchText: "marche"), to: Self.city).map(\.id) == ["osm:1"])
        #expect(SpotFilter.apply(SpotQuery(searchText: "BRIDGE"), to: Self.city).map(\.id) == ["osm:5"])
        #expect(SpotFilter.apply(SpotQuery(searchText: "midtown"), to: Self.city).map(\.id) == ["curated:3"])
        #expect(SpotFilter.apply(SpotQuery(searchText: "  "), to: Self.city).count == Self.city.count)
        #expect(SpotFilter.apply(SpotQuery(searchText: "nowhere"), to: Self.city).isEmpty)
    }

    @Test("Ties break on id, so a redraw never reshuffles the list")
    func tiesAreStable() {
        let a = Self.spot(id: "osm:b", name: "B", score: 0.5)
        let b = Self.spot(id: "osm:a", name: "A", score: 0.5)

        #expect(SpotFilter.apply(SpotQuery(), to: [a, b]).map(\.id) == ["osm:a", "osm:b"])
        #expect(SpotFilter.apply(SpotQuery(), to: [b, a]).map(\.id) == ["osm:a", "osm:b"])
    }
}
