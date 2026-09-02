import Foundation
import Testing
import TDMCore
@testable import TDMSpots

/// The committed bundle, loaded from the test resource.
enum Fixture {
    static let sha256OfSampleJSON = "570f2ba25f5061348955f2a729c8d42f6ae43ba1dd71a7196836d4b9ee61595e"

    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case let .missing(name): "fixture \(name) is not in the test bundle"
            }
        }
    }

    /// The index entry the sample bundle would have in `index.json`.
    static func sampleIndexEntry(bytes: Int) -> CityIndexEntry {
        CityIndexEntry(
            cityId: "us-nyc",
            name: "New York City",
            country: "US",
            lat: 40.7128,
            lon: -74.0060,
            bbox: BoundingBox(minLat: 40.4774, minLon: -74.2591, maxLat: 40.9176, maxLon: -73.7004),
            spotCount: 2,
            bytes: bytes,
            sha256: sha256OfSampleJSON,
            bundleVersion: 3,
            updatedAt: Date(timeIntervalSince1970: 1_756_699_920)
        )
    }
}

@Suite("Bundle fixture — DATA-BUNDLES.md")
struct BundleFixtureTests {
    /// The schema's executable definition. If this fails, either the fixture or
    /// the model moved, and `docs/DATA-BUNDLES.md` is now describing neither.
    @Test("The committed fixture round-trips byte-identically through decode and encode")
    func fixtureRoundTripsByteIdentically() throws {
        let original = try Fixture.data(named: "us-nyc-sample.json")
        let city = try BundleDecoder().decodeCity(json: original)

        var reencoded = try BundleCoding.encoder().encode(city)
        reencoded.append(0x0A)  // the committed file ends with a newline, as text files do

        #expect(reencoded == original)
    }

    @Test("The fixture is a valid two-spot NYC bundle, one curated and one OSM-derived")
    func fixtureIsValid() throws {
        let city = try BundleDecoder().decodeCity(json: try Fixture.data(named: "us-nyc-sample.json"))

        #expect(city.schemaVersion == TDMCore.bundleSchemaVersion)
        #expect(city.cityId == "us-nyc")
        #expect(city.spotCount == 2)
        #expect(city.isValid)
        #expect(city.curatedSpots.count == 1)
        #expect(city.attribution.osm == "© OpenStreetMap contributors, ODbL 1.0")
        #expect(city.spots.allSatisfy { city.bbox.contains($0.coordinate) })

        let curated = try #require(city.spots.first { $0.curated })
        #expect(curated.sources.contains(.curated))
        #expect(curated.openness == .canyon)
        #expect(curated.note?.isEmpty == false)

        let generated = try #require(city.spots.first { !$0.curated })
        #expect(generated.sources == [.osm, .wikidata, .commons])
        #expect(generated.refs["wikidata"] == "Q1163609")
    }

    /// Attribution is not optional: a photo without an author and a licence
    /// cannot be displayed lawfully, so it must not be in the bundle at all.
    @Test("Every photo in the fixture carries an author and a licence")
    func photosAreAttributed() throws {
        let city = try BundleDecoder().decodeCity(json: try Fixture.data(named: "us-nyc-sample.json"))
        let photos = city.spots.flatMap(\.photos)

        #expect(photos.count == 2)
        #expect(photos.allSatisfy { $0.isAttributed })
        #expect(photos.allSatisfy { $0.thumbURL.hasPrefix("https://upload.wikimedia.org/") })
    }

    @Test("Published score factors sum to the published score")
    func scoreFactorsSumToScore() throws {
        let city = try BundleDecoder().decodeCity(json: try Fixture.data(named: "us-nyc-sample.json"))

        for spot in city.spots {
            let total = spot.scoreFactors.map(\.contribution).reduce(0, +)
            #expect(abs(total - spot.score) < 1e-9, "\(spot.id) factors sum to \(total), score is \(spot.score)")
        }
    }
}

@Suite("Bundle decoding — the download path")
struct BundleDecoderTests {
    @Test("A gzipped bundle decompresses, verifies and decodes")
    func decodesCompressedBundle() throws {
        let compressed = try Fixture.data(named: "us-nyc-sample.json.gz")
        let entry = Fixture.sampleIndexEntry(bytes: compressed.count)

        let city = try BundleDecoder().decodeCity(compressed: compressed, entry: entry)

        #expect(city.cityId == "us-nyc")
        #expect(city.spotCount == entry.spotCount)
    }

    /// Never import partial data: a wrong hash discards the whole file, and the
    /// error says which city so the UI can keep showing the previous bundle and
    /// name what failed.
    @Test("A hash mismatch is an error that names the city")
    func hashMismatchNamesTheCity() throws {
        let compressed = try Fixture.data(named: "us-nyc-sample.json.gz")
        var entry = Fixture.sampleIndexEntry(bytes: compressed.count)
        entry.sha256 = String(repeating: "0", count: 64)

        do {
            _ = try BundleDecoder().decodeCity(compressed: compressed, entry: entry)
            Issue.record("Expected a checksum mismatch")
        } catch let error as BundleError {
            guard case let .checksumMismatch(cityId, expected, actual) = error else {
                Issue.record("Expected a checksum mismatch, got \(error)")
                return
            }
            #expect(cityId == "us-nyc")
            #expect(expected == entry.sha256)
            #expect(actual == Fixture.sha256OfSampleJSON)
            #expect(error.description.contains("us-nyc"))
        } catch {
            Issue.record("Expected a checksum mismatch, got \(error)")
        }
    }

    @Test("A truncated download fails before it is decoded")
    func truncatedDownloadFails() throws {
        let compressed = try Fixture.data(named: "us-nyc-sample.json.gz")
        let entry = Fixture.sampleIndexEntry(bytes: compressed.count)

        #expect(throws: BundleError.self) {
            try BundleDecoder().decodeCity(compressed: compressed.dropLast(64), entry: entry)
        }
    }

    @Test("A bundle for the wrong city is refused")
    func cityIdMismatchIsRefused() throws {
        let json = try Fixture.data(named: "us-nyc-sample.json")

        do {
            try BundleDecoder().decodeCity(json: json, expectedCityId: "jp-tokyo")
            Issue.record("Expected a city ID mismatch")
        } catch let error as BundleError {
            #expect(error == .cityIdMismatch(expected: "jp-tokyo", found: "us-nyc"))
        } catch {
            Issue.record("Expected a city ID mismatch, got \(error)")
        }
    }

    @Test("A future schema version is refused rather than half-read")
    func futureSchemaIsRefused() throws {
        let json = try Fixture.data(named: "us-nyc-sample.json")
        let bumped = Data(
            String(decoding: json, as: UTF8.self)
                .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2")
                .utf8
        )

        do {
            try BundleDecoder().decodeCity(json: bumped)
            Issue.record("Expected an unsupported schema version")
        } catch let error as BundleError {
            guard case let .unsupportedSchemaVersion(_, found, supported) = error else {
                Issue.record("Expected an unsupported schema version, got \(error)")
                return
            }
            #expect(found == 2)
            #expect(supported == 1)
        } catch {
            Issue.record("Expected an unsupported schema version, got \(error)")
        }
    }

    @Test("A city is re-downloaded only when the stored version is behind")
    func downloadDecision() {
        let decoder = BundleDecoder()
        let entry = Fixture.sampleIndexEntry(bytes: 1274)

        #expect(decoder.needsDownload(entry: entry, storedBundleVersion: nil))
        #expect(decoder.needsDownload(entry: entry, storedBundleVersion: 2))
        #expect(!decoder.needsDownload(entry: entry, storedBundleVersion: 3))
        #expect(!decoder.needsDownload(entry: entry, storedBundleVersion: 4))
    }
}
