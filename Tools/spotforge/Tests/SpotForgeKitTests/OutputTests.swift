import Foundation
import Testing
import TDMCore
import TDMSpots
@testable import SpotForgeKit

@Suite("Gzip writer")
struct GzipWriterTests {
    /// The app decompresses with `TDMSpots.Gzip`, so that is the only reader
    /// whose opinion matters.
    private func roundTrip(_ data: Data) throws -> Data {
        try Gzip.decompress(GzipWriter.compress(data))
    }

    @Test("A bundle-shaped payload survives the round trip")
    func roundTripsJSON() throws {
        let json = try Data(contentsOf: Fixtures.directory.appendingPathComponent("cities.yml"))
        #expect(try roundTrip(json) == json)
    }

    @Test("Empty, tiny and highly repetitive inputs all round trip")
    func roundTripsEdgeCases() throws {
        #expect(try roundTrip(Data()) == Data())
        #expect(try roundTrip(Data([0x41])) == Data([0x41]))

        let repetitive = Data(String(repeating: "the same sentence, again. ", count: 4_000).utf8)
        #expect(try roundTrip(repetitive) == repetitive)
        // Repetition is the whole point of DEFLATE; if this is not far smaller
        // the matcher is not matching.
        #expect(GzipWriter.compress(repetitive).count < repetitive.count / 10)
    }

    @Test("Binary input round trips too")
    func roundTripsBinary() throws {
        var bytes: [UInt8] = []
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        for _ in 0..<20_000 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes.append(UInt8(truncatingIfNeeded: state))
        }
        let data = Data(bytes)
        #expect(try roundTrip(data) == data)
    }

    @Test("The same bytes compress to the same file every time")
    func isReproducible() {
        let data = Data(String(repeating: "reproducible", count: 500).utf8)
        #expect(GzipWriter.compress(data) == GzipWriter.compress(data))
    }
}

@Suite("Bundle writing and validation")
struct BundleWriterTests {
    private func city(id: String = "us-nyc", spots: [Spot]) -> City {
        City(
            cityId: id,
            name: "New York City",
            country: "US",
            bundleVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generator: "spotforge tests",
            bbox: Fixtures.bbox,
            attribution: Attribution(osm: "© OpenStreetMap contributors, ODbL 1.0"),
            spots: spots
        )
    }

    private var sampleSpot: Spot {
        Spot(
            id: "osm:node/1",
            name: "Somewhere",
            lat: 40.7305,
            lon: -73.997,
            kind: .street,
            sources: [.osm],
            score: 0.5,
            openness: .open
        )
    }

    @Test("A written bundle decodes with the app's decoder and its hash matches")
    func writesDecodableBundle() throws {
        let directory = try Fixtures.temporaryDirectory("writer")
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = BundleWriter(outputDirectory: directory)
        let written = try writer.write(city(spots: [sampleSpot]))
        _ = try writer.writeIndex(updating: [written.entry], generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let decoder = BundleDecoder()
        let compressed = try Data(contentsOf: written.bundleURL)
        let decoded = try decoder.decodeCity(compressed: compressed, entry: written.entry)
        #expect(decoded.cityId == "us-nyc")
        #expect(decoded.spots.count == 1)

        // The checksum in the index is over the decompressed JSON, per
        // docs/DATA-BUNDLES.md, so it survives a different compressor.
        let json = try Gzip.decompress(compressed)
        #expect(written.entry.sha256 == SHA256.hexDigest(json))
        #expect(written.jsonBytes == json.count)

        let result = BundleValidator(directory: directory).validate()
        #expect(result.isValid)
        #expect(result.cities.count == 1)
        #expect(result.cities.first?.hasPrefix("us-nyc") == true)
        #expect(result.spotCount == 1)
    }

    @Test("Writing one city leaves the other index entries alone")
    func indexKeepsOtherCities() throws {
        let directory = try Fixtures.temporaryDirectory("index")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = BundleWriter(outputDirectory: directory)

        let nyc = try writer.write(city(spots: [sampleSpot]))
        _ = try writer.writeIndex(updating: [nyc.entry], generatedAt: Date())
        let london = try writer.write(city(id: "gb-lon", spots: [sampleSpot]))
        let index = try writer.writeIndex(updating: [london.entry], generatedAt: Date())

        #expect(index.cities.map(\.cityId) == ["gb-lon", "us-nyc"])
        #expect(writer.nextBundleVersion(for: "us-nyc") == 2)
        #expect(writer.nextBundleVersion(for: "fr-par") == 1)
    }

    @Test("A corrupted bundle is caught by the hash, not by the decoder")
    func detectsTampering() throws {
        let directory = try Fixtures.temporaryDirectory("tamper")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = BundleWriter(outputDirectory: directory)

        let written = try writer.write(city(spots: [sampleSpot]))
        var entry = written.entry
        entry.sha256 = String(repeating: "0", count: 64)
        _ = try writer.writeIndex(updating: [entry], generatedAt: Date())

        let result = BundleValidator(directory: directory).validate()
        #expect(!result.isValid)
        #expect(result.problems.contains { $0.lowercased().contains("checksum") })
    }

    @Test("A missing bundle file is a validation problem, not a crash")
    func detectsMissingBundle() throws {
        let directory = try Fixtures.temporaryDirectory("missing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = BundleWriter(outputDirectory: directory)

        let written = try writer.write(city(spots: [sampleSpot]))
        _ = try writer.writeIndex(updating: [written.entry], generatedAt: Date())
        try FileManager.default.removeItem(at: written.bundleURL)

        let result = BundleValidator(directory: directory).validate()
        #expect(!result.isValid)
    }
}

@Suite("Command line")
struct CommandLineTests {
    @Test("A build parses its cities and paths")
    func parsesBuild() throws {
        let command = try CommandLineInterface.parse([
            "build", "--city", "us-nyc", "--city", "gb-lon",
            "--out", "bundles/v1", "--cities", "data/cities.yml",
            "--curated", "data/curated", "--report", "--strict", "--no-photos"
        ])
        guard case .build(let request) = command else {
            Issue.record("Expected a build command")
            return
        }
        #expect(request.scope == .cities(["us-nyc", "gb-lon"]))
        #expect(request.outputDirectory == "bundles/v1")
        #expect(request.citiesPath == "data/cities.yml")
        #expect(request.curatedDirectory == "data/curated")
        #expect(request.printsReport)
        #expect(request.strict)
        #expect(!request.fetchesPhotos)
    }

    @Test("--all builds every declared city")
    func parsesAll() throws {
        guard case .build(let request) = try CommandLineInterface.parse(["build", "--all"]) else {
            Issue.record("Expected a build command")
            return
        }
        #expect(request.scope == .allCities)
        #expect(request.outputDirectory == "bundles/v1")
    }

    @Test("validate takes a directory and defaults to the bundle root")
    func parsesValidate() throws {
        guard case .validate(let directory) = try CommandLineInterface.parse(["validate", "out/v1"]) else {
            Issue.record("Expected a validate command")
            return
        }
        #expect(directory == "out/v1")

        guard case .validate(let fallback) = try CommandLineInterface.parse(["validate"]) else {
            Issue.record("Expected a validate command")
            return
        }
        #expect(fallback == "bundles/v1")
    }

    @Test("Bad arguments are refused rather than guessed at")
    func refusesBadArguments() {
        #expect(throws: ArgumentError.self) { try CommandLineInterface.parse([]) }
        #expect(throws: ArgumentError.self) { try CommandLineInterface.parse(["frobnicate"]) }
        #expect(throws: ArgumentError.self) { try CommandLineInterface.parse(["build", "--city"]) }
        #expect(throws: ArgumentError.self) { try CommandLineInterface.parse(["build"]) }
        #expect(throws: ArgumentError.self) { try CommandLineInterface.parse(["build", "--all", "--nonsense"]) }
    }
}

@Suite("Request runner")
struct RequestRunnerTests {
    private struct SpyTransport: Transport {
        let seen: Recorder

        actor Recorder {
            private(set) var requests: [HTTPRequest] = []
            func record(_ request: HTTPRequest) { requests.append(request) }
            var count: Int { requests.count }
            var userAgents: [String] { requests.compactMap { $0.headers["User-Agent"] } }
        }

        func send(_ request: HTTPRequest) async throws -> Data {
            await seen.record(request)
            return Data(#"{"ok":true}"#.utf8)
        }
    }

    @Test("Every request carries a User-Agent with a contact route")
    func identifiesItself() async throws {
        let recorder = SpyTransport.Recorder()
        let runner = RequestRunner(
            transport: SpyTransport(seen: recorder),
            cacheDirectory: nil,
            minimumInterval: 0
        )
        _ = try await runner.send(HTTPRequest(url: URL(string: "https://example.org/a")!), cacheNamespace: "test")

        let agents = await recorder.userAgents
        #expect(agents.count == 1)
        let agent = try #require(agents.first)
        #expect(agent.contains("spotforge/"))
        #expect(agent.contains("github.com/ViktorWill/TheDecisiveMoment"))
    }

    @Test("A repeated query is served from the disk cache")
    func cachesByQueryHash() async throws {
        let cache = try Fixtures.temporaryDirectory("cache")
        defer { try? FileManager.default.removeItem(at: cache) }

        let recorder = SpyTransport.Recorder()
        let runner = RequestRunner(
            transport: SpyTransport(seen: recorder),
            cacheDirectory: cache,
            minimumInterval: 0
        )
        let request = HTTPRequest(url: URL(string: "https://example.org/a")!)
        _ = try await runner.send(request, cacheNamespace: "test")
        _ = try await runner.send(request, cacheNamespace: "test")

        #expect(await recorder.count == 1)
        #expect(await runner.requestCount == 1)
        #expect(await runner.cacheHitCount == 1)
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("test/\(request.cacheKey).json").path))
    }

    @Test("The cache key ignores the User-Agent but follows the query")
    func cacheKeyFollowsTheQuery() {
        let base = HTTPRequest(url: URL(string: "https://example.org/a")!)
        var identified = base
        identified.headers["User-Agent"] = "someone else"
        #expect(base.cacheKey == identified.cacheKey)

        let other = HTTPRequest(url: URL(string: "https://example.org/b")!)
        #expect(base.cacheKey != other.cacheKey)

        let posted = HTTPRequest(url: base.url, method: "POST", body: Data("query".utf8))
        #expect(posted.cacheKey != base.cacheKey)
    }
}
