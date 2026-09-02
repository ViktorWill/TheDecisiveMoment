import Foundation
import Testing
@testable import TDMCore

@Suite("Geography")
struct GeographyTests {
    /// Two independent references. One degree of latitude on a sphere of
    /// radius 6 371 008.8 m is 111 195.08 m by construction (`2πR/360`), and the
    /// Empire State Building (40.748440, -73.985664) to Washington Square Arch
    /// (40.730823, -73.997332) is 2 191.74 m, computed with the same haversine
    /// in an independent implementation.
    @Test("Great-circle distance matches known separations")
    func distanceIsPlausible() {
        let empireState = Coordinate(latitude: 40.748440, longitude: -73.985664)
        let arch = Coordinate(latitude: 40.730823, longitude: -73.997332)

        let oneDegreeOfLatitude = Coordinate(latitude: 51.5, longitude: 0)
            .distance(to: Coordinate(latitude: 52.5, longitude: 0))
        #expect(abs(oneDegreeOfLatitude - 111_195.08) < 0.1)
        #expect(abs(empireState.distance(to: arch) - 2191.74) < 0.1)
        #expect(empireState.distance(to: empireState) == 0)
        // Symmetric, because the merge rule depends on it being so.
        #expect(empireState.distance(to: arch) == arch.distance(to: empireState))
    }

    /// A swapped pair fails whenever the longitude was outside ±90°, which is
    /// most of the world — though not New York, where both values happen to be
    /// legal latitudes. Validation is a cheap net, not a proof.
    @Test("Ranges are checked, which catches most swapped pairs")
    func validationCatchesSwappedPairs() {
        #expect(Coordinate(latitude: 35.6762, longitude: 139.6503).isValid)
        #expect(!Coordinate(latitude: 139.6503, longitude: 35.6762).isValid)
        #expect(!Coordinate(latitude: 0, longitude: 181).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
    }

    @Test("A bounding box contains what it should")
    func boundingBoxContainment() {
        let nyc = BoundingBox(minLat: 40.4774, minLon: -74.2591, maxLat: 40.9176, maxLon: -73.7004)

        #expect(nyc.isValid)
        #expect(nyc.contains(Coordinate(latitude: 40.7128, longitude: -74.0060)))
        #expect(!nyc.contains(Coordinate(latitude: 48.8566, longitude: 2.3522)))
        #expect(abs(nyc.center.latitude - 40.6975) < 1e-9)
        #expect(!BoundingBox(minLat: 41, minLon: 0, maxLat: 40, maxLon: 1).isValid)
    }

    @Test("Unioning boxes covers both")
    func boundingBoxUnion() {
        let manhattan = BoundingBox(minLat: 40.698, minLon: -74.020, maxLat: 40.880, maxLon: -73.907)
        let brooklyn = BoundingBox(minLat: 40.570, minLon: -74.042, maxLat: 40.7395, maxLon: -73.833)
        let both = manhattan.union(brooklyn)

        #expect(both == BoundingBox(minLat: 40.570, minLon: -74.042, maxLat: 40.880, maxLon: -73.833))
        #expect(both.contains(manhattan.center))
        #expect(both.contains(brooklyn.center))
    }

    @Test("A coordinate codes as the bundle's lat/lon pair")
    func coordinateCodingKeys() throws {
        let json = Data(#"{"lat":40.7128,"lon":-74.006}"#.utf8)
        let coordinate = try JSONDecoder().decode(Coordinate.self, from: json)

        #expect(coordinate == Coordinate(latitude: 40.7128, longitude: -74.006))
    }
}

@Suite("City index — SPEC-map.md city detection")
struct CityIndexTests {
    static func entry(_ id: String, lat: Double, lon: Double, box: BoundingBox) -> CityIndexEntry {
        CityIndexEntry(
            cityId: id,
            name: id,
            country: String(id.prefix(2)).uppercased(),
            lat: lat,
            lon: lon,
            bbox: box,
            spotCount: 100,
            bytes: 184_320,
            sha256: String(repeating: "9f", count: 32),
            bundleVersion: 3,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static let index = CityIndex(
        generatedAt: Date(timeIntervalSince1970: 0),
        cities: [
            entry("us-nyc", lat: 40.7128, lon: -74.0060, box: BoundingBox(minLat: 40.4774, minLon: -74.2591, maxLat: 40.9176, maxLon: -73.7004)),
            // A deliberately overlapping neighbour: Manhattan sits inside both.
            entry("us-newark", lat: 40.7357, lon: -74.1724, box: BoundingBox(minLat: 40.60, minLon: -74.30, maxLat: 40.85, maxLon: -73.90)),
            entry("jp-tokyo", lat: 35.6762, lon: 139.6503, box: BoundingBox(minLat: 35.5, minLon: 139.3, maxLat: 35.9, maxLon: 139.9))
        ]
    )

    @Test("Where several boxes match, the nearest centre wins")
    func nearestCentreWins() {
        let midtown = Coordinate(latitude: 40.7535, longitude: -73.9813)
        #expect(Self.index.city(containing: midtown)?.cityId == "us-nyc")

        let acrossTheRiver = Coordinate(latitude: 40.7357, longitude: -74.1724)
        #expect(Self.index.city(containing: acrossTheRiver)?.cityId == "us-newark")
    }

    @Test("No match is a plain nil, not a nearest guess")
    func noMatchIsNil() {
        #expect(Self.index.city(containing: Coordinate(latitude: -33.8688, longitude: 151.2093)) == nil)
    }

    @Test("The picker lists every city, nearest first")
    func pickerOrder() {
        let order = Self.index.citiesSortedByDistance(from: Coordinate(latitude: 35.68, longitude: 139.75))
        #expect(order.first?.cityId == "jp-tokyo")
        #expect(order.count == 3)
    }

    @Test("An index entry knows where its bundle lives and whether it is well formed")
    func entryValidation() throws {
        let entry = try #require(Self.index.entry(for: "us-nyc"))

        #expect(entry.bundlePath == "cities/us-nyc.json.gz")
        #expect(entry.isValid)

        var broken = entry
        broken.sha256 = "9F2B1C"
        #expect(!broken.isValid)
    }
}

@Suite("Spot validation")
struct SpotValidationTests {
    static func sample() -> Spot {
        Spot(
            id: "osm:node/357555716",
            name: "Washington Square Arch",
            lat: 40.73096,
            lon: -73.99725,
            kind: .plaza,
            sources: [.osm],
            score: 0.87,
            bestHours: [7, 8],
            streetBearing: 15,
            openness: .open,
            photos: [SpotPhoto(thumbURL: "https://example.org/t.jpg", pageURL: "https://example.org/p", author: "Jane Example", license: "CC BY-SA 4.0")]
        )
    }

    @Test("A well-formed spot validates")
    func wellFormedSpot() {
        let spot = Self.sample()

        #expect(spot.isValid)
        #expect(spot.idSource == "osm")
        #expect(spot.coordinate == Coordinate(latitude: 40.73096, longitude: -73.99725))
    }

    @Test("Out-of-range values are caught")
    func outOfRangeValues() {
        var spot = Self.sample()

        spot.score = 1.4
        #expect(!spot.isValid)

        spot = Self.sample()
        spot.bestHours = [7, 24]
        #expect(!spot.isValid)

        spot = Self.sample()
        // Bearings are normalised to 0–180: a street axis has no direction.
        spot.streetBearing = 275
        #expect(!spot.isValid)
    }

    /// Attribution is not optional, so a photo missing it makes the spot
    /// invalid rather than merely rendering oddly.
    @Test("A photo without a licence invalidates its spot")
    func unattributedPhoto() {
        var spot = Self.sample()
        spot.photos[0].license = " "

        #expect(!spot.photos[0].isAttributed)
        #expect(!spot.isValid)
    }

    @Test("Optional fields are omitted rather than written as null")
    func optionalFieldsAreOmitted() throws {
        var spot = Self.sample()
        spot.bestHours = nil
        spot.streetBearing = nil
        spot.note = nil

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(spot), as: UTF8.self)

        #expect(!json.contains("null"))
        #expect(!json.contains("bestHours"))
        #expect(!json.contains("streetBearing"))
    }

    @Test("A spot decodes when the optional and defaulted fields are absent")
    func minimalSpotDecodes() throws {
        let json = Data(#"{"id":"osm:1","name":"A","lat":1,"lon":2,"kind":"street","score":0.1}"#.utf8)
        let spot = try JSONDecoder().decode(Spot.self, from: json)

        #expect(spot.openness == .open)
        #expect(spot.tags.isEmpty)
        #expect(spot.bestHours == nil)
        #expect(!spot.curated)
    }
}
