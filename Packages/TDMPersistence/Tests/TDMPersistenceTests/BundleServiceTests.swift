import Foundation
import Synchronization
import Testing
import TDMCore
import TDMSpots
@testable import TDMPersistence

@Suite("Bundle download flow — DATA-BUNDLES.md, SPEC-map.md")
struct BundleServiceTests {
    // MARK: - Fixtures

    static let generatedAt = Date(timeIntervalSince1970: 1_756_800_000)

    static func city(bundleVersion: Int = 3, spots: [Spot]? = nil) -> City {
        City(
            cityId: "us-nyc",
            name: "New York City",
            country: "US",
            bundleVersion: bundleVersion,
            generatedAt: generatedAt,
            generator: "spotforge 0.1.0",
            bbox: BoundingBox(minLat: 40.4774, minLon: -74.2591, maxLat: 40.9176, maxLon: -73.7004),
            attribution: Attribution(
                osm: "© OpenStreetMap contributors, ODbL 1.0",
                wikidata: "Wikidata, CC0 1.0",
                commons: "Wikimedia Commons — per-file licence in photo entries"
            ),
            spots: spots ?? [
                Spot(
                    id: "osm:node/357555716",
                    name: "Washington Square Arch",
                    lat: 40.73096,
                    lon: -73.99725,
                    kind: .plaza,
                    sources: [.osm, .curated],
                    score: 0.87,
                    tags: ["crowds", "arch"],
                    bestHours: [7, 8, 16, 17],
                    streetBearing: 15,
                    openness: .open,
                    note: "Arch frames northward up Fifth Avenue.",
                    curated: true
                )
            ]
        )
    }

    static func encoded(_ city: City) throws -> (json: Data, gzip: Data, sha256: String) {
        let json = try BundleCoding.encoder().encode(city)
        return (json, GzipWriter.compress(json), SHA256.hexDigest(json))
    }

    static func index(for city: City, sha256: String, bytes: Int) -> CityIndex {
        CityIndex(
            generatedAt: generatedAt,
            cities: [
                CityIndexEntry(
                    cityId: city.cityId,
                    name: city.name,
                    country: city.country,
                    lat: 40.7128,
                    lon: -74.0060,
                    bbox: city.bbox,
                    spotCount: city.spots.count,
                    bytes: bytes,
                    sha256: sha256,
                    bundleVersion: city.bundleVersion,
                    updatedAt: generatedAt
                )
            ]
        )
    }

    /// Recorded responses, keyed by path, with a count of what was asked for —
    /// the cache rules are about what is *not* fetched.
    final class RecordingTransport: BundleTransport, Sendable {
        private struct State {
            var responses: [String: Result<Data, any Error>] = [:]
            var requests: [String] = []
        }

        private let state = Mutex(State())

        init(responses: [String: Result<Data, any Error>]) {
            state.withLock { $0.responses = responses }
        }

        func data(from url: URL) async throws -> Data {
            let key = url.lastPathComponent
            let result: Result<Data, any Error>? = state.withLock {
                $0.requests.append(key)
                return $0.responses[key]
            }
            switch result {
            case let .success(data): return data
            case let .failure(error): throw error
            case nil: throw BundleTransportError.http(statusCode: 404, url: url)
            }
        }

        var requests: [String] { state.withLock { $0.requests } }
        func requestCount(for name: String) -> Int { requests.filter { $0 == name }.count }
    }

    struct Offline: Error {}

    static func service(
        store: InMemorySpotStore,
        responses: [String: Result<Data, any Error>],
        now: Date = generatedAt
    ) -> (BundleService, RecordingTransport) {
        let transport = RecordingTransport(responses: responses)
        let service = BundleService(
            store: store,
            transport: transport,
            source: BundleSource(root: URL(string: "https://example.invalid/bundles/v1/")!),
            clock: { now }
        )
        return (service, transport)
    }

    // MARK: - Tests

    @Test("Fetch, verify, decode, import — the whole client path")
    func importsAVerifiedBundle() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        let (service, _) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])

        let outcome = try await service.refresh(cityId: "us-nyc")

        #expect(outcome == .imported(cityId: "us-nyc", bundleVersion: 3, spotCount: 1))
        #expect(await store.storedBundleVersion(cityId: "us-nyc") == 3)
        let summary = await store.storedCity(cityId: "us-nyc")
        #expect(summary?.spotCount == 1)
        #expect(summary?.attribution.osm == "© OpenStreetMap contributors, ODbL 1.0")
    }

    @Test("The index is cached for an hour")
    func indexIsCachedForAnHour() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore(clock: { Self.generatedAt })
        let (service, transport) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index))
        ])

        _ = try await service.index()
        _ = try await service.index()

        #expect(transport.requestCount(for: "index.json") == 1)
    }

    @Test("An hour later it is fetched again")
    func indexRefreshesAfterTheHour() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore(clock: { Self.generatedAt })
        let data = try BundleCoding.encoder().encode(index)
        let transport = RecordingTransport(responses: ["index.json": .success(data)])
        let stale = BundleService(
            store: store,
            transport: transport,
            source: BundleSource(root: URL(string: "https://example.invalid/bundles/v1/")!),
            clock: { Self.generatedAt.addingTimeInterval(3_601) }
        )

        _ = try await stale.index()
        _ = try await stale.index()

        // The first call stores the index at the fixed store clock, an hour and
        // a second before "now", so both calls are outside the cache.
        #expect(transport.requestCount(for: "index.json") == 2)
    }

    @Test("With no network, the stored index still answers")
    func offlineFallsBackToTheStoredIndex() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore(clock: { Self.generatedAt })
        await store.store(index)
        let (service, _) = Self.service(
            store: store,
            responses: ["index.json": .failure(Offline())],
            now: Self.generatedAt.addingTimeInterval(86_400)
        )

        let fetched = try await service.index()

        #expect(fetched.cities.map(\.cityId) == ["us-nyc"])
    }

    @Test("A city is resolved from a coarse fix")
    func resolvesTheCityFromACoordinate() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        let (service, _) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index))
        ])

        let manhattan = try await service.city(containing: Coordinate(latitude: 40.7580, longitude: -73.9855))
        let alps = try await service.city(containing: Coordinate(latitude: 46.8, longitude: 8.2))

        #expect(manhattan?.cityId == "us-nyc")
        #expect(alps == nil)
    }

    @Test("A corrupted download is refused and the previous bundle survives")
    func aBadChecksumKeepsThePreviousBundle() async throws {
        let stored = Self.city(bundleVersion: 3)
        let store = InMemorySpotStore()
        try await store.replaceSpots(for: "us-nyc", with: stored)

        let next = Self.city(bundleVersion: 4, spots: [])
        let encoded = try Self.encoded(next)
        var index = Self.index(for: next, sha256: encoded.sha256, bytes: encoded.gzip.count)
        index.cities[0].sha256 = String(repeating: "a", count: 64)
        let (service, _) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])

        await #expect(throws: BundleRefreshError.self) {
            try await service.refresh(cityId: "us-nyc")
        }
        #expect(await store.storedBundleVersion(cityId: "us-nyc") == 3)
        #expect(await store.storedCity(cityId: "us-nyc")?.spotCount == 1)
    }

    @Test("A failed download names the city that failed")
    func failuresNameTheCity() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        let (service, _) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .failure(Offline())
        ])

        do {
            _ = try await service.refresh(cityId: "us-nyc")
            Issue.record("a failed download should throw")
        } catch let error as BundleRefreshError {
            #expect(error.cityId == "us-nyc")
            #expect(error.description.contains("us-nyc"))
            #expect(error.description.contains("unchanged"))
        }
    }

    @Test("A city the index does not list says so rather than 404ing")
    func unknownCity() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        let (service, transport) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index))
        ])

        do {
            _ = try await service.refresh(cityId: "jp-tokyo")
            Issue.record("an unlisted city should throw")
        } catch let error as BundleRefreshError {
            #expect(error.cityId == "jp-tokyo")
        }
        #expect(!transport.requests.contains("jp-tokyo.json.gz"))
    }

    @Test("A current bundle is not downloaded again")
    func currentBundlesAreNotRefetched() async throws {
        let city = Self.city()
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        try await store.replaceSpots(for: "us-nyc", with: city)
        let (service, transport) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])

        let outcome = try await service.refresh(cityId: "us-nyc")

        #expect(outcome == .alreadyCurrent(cityId: "us-nyc", bundleVersion: 3))
        #expect(transport.requestCount(for: "us-nyc.json.gz") == 0)
    }

    @Test("A stored city at the index version asks for nothing at all")
    func aCurrentStoredCityNeedsNoDownload() async throws {
        let city = Self.city(bundleVersion: 3)
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore()
        try await store.replaceSpots(for: "us-nyc", with: city)
        let (service, transport) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])
        let entry = try #require(try await service.index().entry(for: "us-nyc"))

        #expect(await service.needsDownload(entry: entry) == false)
        #expect(try await service.refresh(entry: entry) == .alreadyCurrent(cityId: "us-nyc", bundleVersion: 3))
        #expect(transport.requestCount(for: "us-nyc.json.gz") == 0)
    }

    @Test("A bumped bundleVersion is offered, and imported only when asked for")
    func aBumpedBundleVersionIsOffered() async throws {
        let store = InMemorySpotStore()
        try await store.replaceSpots(for: "us-nyc", with: Self.city(bundleVersion: 3))

        let next = Self.city(bundleVersion: 4, spots: [
            Spot(
                id: "osm:node/1", name: "Bethesda Terrace", lat: 40.7740, lon: -73.9709,
                kind: .plaza, sources: [.osm], score: 0.71
            ),
            Spot(
                id: "osm:node/2", name: "Fifth Avenue", lat: 40.7735, lon: -73.9660,
                kind: .street, sources: [.osm], score: 0.62
            )
        ])
        let encoded = try Self.encoded(next)
        let index = Self.index(for: next, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let (service, transport) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])
        let entry = try #require(try await service.index().entry(for: "us-nyc"))

        // Asking is free: the check itself never reaches for the bundle.
        #expect(await service.needsDownload(entry: entry) == true)
        #expect(transport.requestCount(for: "us-nyc.json.gz") == 0)

        let outcome = try await service.refresh(entry: entry)

        #expect(outcome == .imported(cityId: "us-nyc", bundleVersion: 4, spotCount: 2))
        #expect(await store.storedBundleVersion(cityId: "us-nyc") == 4)
        #expect(await store.storedCity(cityId: "us-nyc")?.spotCount == 2)
    }

    @Test("With no network, the update check is silent and the stored bundle stands")
    func offlineTheCheckNeitherDownloadsNorFails() async throws {
        let city = Self.city(bundleVersion: 3)
        let encoded = try Self.encoded(city)
        let index = Self.index(for: city, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let store = InMemorySpotStore(clock: { Self.generatedAt })
        await store.store(index)
        try await store.replaceSpots(for: "us-nyc", with: city)
        let (service, transport) = Self.service(
            store: store,
            responses: ["index.json": .failure(Offline())],
            now: Self.generatedAt.addingTimeInterval(86_400)
        )
        let entry = try #require(try await service.index().entry(for: "us-nyc"))

        #expect(await service.needsDownload(entry: entry) == false)
        #expect(transport.requestCount(for: "us-nyc.json.gz") == 0)
        #expect(await store.storedCity(cityId: "us-nyc")?.bundleVersion == 3)
    }

    @Test("A dropped pin survives a bundle refresh")    func pinsSurviveARefresh() async throws {
        let store = InMemorySpotStore()
        let pin = LocalPin.make(
            id: "local:abc",
            name: "My corner",
            coordinate: Coordinate(latitude: 40.7300, longitude: -73.9950)
        )
        try await store.upsertPin(pin)
        try await store.replaceSpots(for: "us-nyc", with: Self.city(bundleVersion: 3))

        let next = Self.city(bundleVersion: 4)
        let encoded = try Self.encoded(next)
        let index = Self.index(for: next, sha256: encoded.sha256, bytes: encoded.gzip.count)
        let (service, _) = Self.service(store: store, responses: [
            "index.json": .success(try BundleCoding.encoder().encode(index)),
            "us-nyc.json.gz": .success(encoded.gzip)
        ])

        _ = try await service.refresh(cityId: "us-nyc")

        #expect(await store.pins().map(\.id) == ["local:abc"])
        let visible = await store.spots(in: "us-nyc", matching: SpotQuery())
        #expect(visible.contains { $0.id == "local:abc" })
    }

    @Test("A bundle spot cannot be stored as a pin")
    func onlyLocalIdsArePins() async throws {
        let store = InMemorySpotStore()
        let bundled = Self.city().spots[0]

        await #expect(throws: SpotStoreError.notALocalPin(id: bundled.id)) {
            try await store.upsertPin(bundled)
        }
    }

    @Test("The store answers a bounding box, not a city")
    func queriesAreByBoundingBox() async throws {
        let store = InMemorySpotStore()
        let downtown = Spot(
            id: "osm:1", name: "Downtown", lat: 40.71, lon: -74.01, kind: .plaza,
            sources: [.osm], score: 0.5
        )
        let uptown = Spot(
            id: "osm:2", name: "Uptown", lat: 40.81, lon: -73.95, kind: .plaza,
            sources: [.osm], score: 0.9
        )
        try await store.replaceSpots(for: "us-nyc", with: Self.city(spots: [downtown, uptown]))

        let query = SpotQuery(
            boundingBox: BoundingBox(minLat: 40.70, minLon: -74.02, maxLat: 40.75, maxLon: -73.98)
        )

        #expect(await store.spots(in: "us-nyc", matching: query).map(\.id) == ["osm:1"])
    }
}
