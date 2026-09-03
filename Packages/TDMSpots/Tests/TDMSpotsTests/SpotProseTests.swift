import Foundation
import Testing
import TDMCore
@testable import TDMSpots

@Suite("Prose, pins and export — SPEC-map.md")
struct SpotProseTests {
    static let arch = Spot(
        id: "osm:node/357555716",
        name: "Washington Square Arch",
        lat: 40.73096,
        lon: -73.99725,
        kind: .plaza,
        sources: [.osm, .wikidata, .commons, .curated],
        score: 0.87,
        scoreFactors: [
            ScoreFactor(kind: .photoDensity, contribution: 0.42, detail: "137 geotagged photos within 150 m"),
            ScoreFactor(kind: .notability, contribution: 0.20, detail: "Wikidata: Q1163609"),
            ScoreFactor(kind: .featurePrior, contribution: 0.15, detail: "plaza"),
            ScoreFactor(kind: .curation, contribution: 0.10, detail: "curated: NYC canon")
        ],
        tags: ["crowds", "arch"],
        openness: .open,
        curated: true
    )

    @Test("The score reads as a sentence, never as a number")
    func scoreIsProse() {
        let summary = SpotProse.scoreSummary(for: Self.arch)

        #expect(summary == "137 photos nearby · plaza · notable · curated")
        #expect(!summary.contains("0.87"))
    }

    @Test("The detail header names the sky instead of repeating the badge")
    func detailSummaryNamesOpenness() {
        #expect(SpotProse.detailSummary(for: Self.arch) == "137 photos nearby · plaza · notable · open sky")
    }

    @Test("A spot with no factors still says what it is")
    func summaryWithoutFactors() {
        let bare = Spot(id: "osm:1", name: "A corner", lat: 40.7, lon: -74, kind: .intersection, sources: [.osm], score: 0.2)

        #expect(SpotProse.scoreSummary(for: bare) == "intersection")
    }

    @Test("Distances round to what a walk can tell apart")
    func distanceFormatting() {
        #expect(SpotProse.distance(metres: 243) == "240 m")
        #expect(SpotProse.distance(metres: 1_140) == "1.1 km")
        #expect(SpotProse.distance(metres: 12_400) == "12 km")
    }

    @Test("240 m is a three-minute walk, as in the mockup")
    func walkingTime() {
        #expect(SpotProse.walkingTime(metres: 240) == "3 min walk")
        #expect(SpotProse.walkingTime(metres: 10) == "1 min walk")
    }

    @Test("A dropped pin is local, unhideable by the floor, and axis-folded")
    func pinsAreLocal() {
        let pin = LocalPin.make(
            name: "My corner",
            coordinate: Coordinate(latitude: 40.73, longitude: -73.99),
            kind: .street,
            openness: .canyon,
            tags: ["quiet"],
            note: "Morning light down the block",
            streetBearingDegrees: 200
        )

        #expect(LocalPin.isLocal(id: pin.id))
        #expect(pin.sources == [.local])
        #expect(pin.score == 1)
        #expect(pin.streetBearing == 20)
        #expect(pin.isValid)
        #expect(SpotProse.scoreSummary(for: pin) == "street · your pin")
    }

    @Test("Export is RFC 7946: longitude first")
    func geoJSONOrdersLongitudeFirst() throws {
        let pin = LocalPin.make(
            id: "local:abc",
            name: "My corner",
            coordinate: Coordinate(latitude: 40.73096, longitude: -73.99725)
        )

        let data = try GeoJSONExport.featureCollection([pin])
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let features = decoded?["features"] as? [[String: Any]]
        let geometry = features?.first?["geometry"] as? [String: Any]
        let coordinates = geometry?["coordinates"] as? [Double]

        #expect(decoded?["type"] as? String == "FeatureCollection")
        #expect(coordinates == [-73.99725, 40.73096])
        #expect(text.contains("\"id\" : \"local:abc\""))
    }

    @Test("The export file name sorts by date")
    func exportFileName() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 3
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)

        #expect(GeoJSONExport.fileName(date: date, calendar: calendar) == "the-decisive-moment-pins-2026-09-03.geojson")
    }
}
