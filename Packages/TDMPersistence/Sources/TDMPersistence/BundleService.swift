import Foundation
import TDMCore
import TDMSpots

/// Why a refresh failed, and for which city.
///
/// Every case names the city, because the rule of `docs/SPEC-map.md` is that a
/// failure keeps the previous bundle and *says which one failed* — a map that
/// silently kept yesterday's data is a map you cannot trust in a strange city.
public enum BundleRefreshError: Error, Sendable, CustomStringConvertible {
    /// `index.json` could not be fetched and nothing was stored to fall back on.
    case indexUnavailable(reason: String)
    /// The index does not list this city.
    case unknownCity(cityId: String)
    /// The bytes never arrived. The previous bundle, if any, is untouched.
    case downloadFailed(cityId: String, reason: String)
    /// They arrived and were refused — checksum, schema or shape.
    case rejected(cityId: String, underlying: BundleError)
    /// They decoded and the import failed.
    case importFailed(cityId: String, reason: String)

    public var cityId: String? {
        switch self {
        case .indexUnavailable: nil
        case let .unknownCity(cityId): cityId
        case let .downloadFailed(cityId, _): cityId
        case let .rejected(cityId, _): cityId
        case let .importFailed(cityId, _): cityId
        }
    }

    public var description: String {
        switch self {
        case let .indexUnavailable(reason):
            "The city list could not be fetched (\(reason))."
        case let .unknownCity(cityId):
            "\(cityId) is not in the city list."
        case let .downloadFailed(cityId, reason):
            "\(cityId) could not be downloaded (\(reason)). The stored bundle is unchanged."
        case let .rejected(_, underlying):
            "\(underlying.description) The stored bundle is unchanged."
        case let .importFailed(cityId, reason):
            "\(cityId) downloaded but could not be stored (\(reason)). The stored bundle is unchanged."
        }
    }
}

/// What a refresh did.
public enum BundleRefreshOutcome: Sendable, Equatable {
    /// The stored bundle is already at the index's version; nothing was fetched.
    case alreadyCurrent(cityId: String, bundleVersion: Int)
    case imported(cityId: String, bundleVersion: Int, spotCount: Int)

    public var cityId: String {
        switch self {
        case let .alreadyCurrent(cityId, _): cityId
        case let .imported(cityId, _, _): cityId
        }
    }
}

/// The download flow of `docs/DATA-BUNDLES.md` ("Client rules"): fetch the
/// index, resolve a city, download, verify, decode, import — and on any failure
/// keep what is stored.
///
/// It holds a ``TDMSpots/SpotStore`` rather than SwiftData directly, so the
/// whole flow is exercised on Linux against an in-memory store and a recorded
/// transport. There is no network call here that a stored bundle does not make
/// optional: the offline path never waits for this.
public actor BundleService {
    /// `index.json` is cached for an hour, per `docs/DATA-BUNDLES.md`.
    public static let indexCacheDuration: TimeInterval = 3_600

    private let source: BundleSource
    private let transport: any BundleTransport
    private let store: any SpotStore
    private let decoder: BundleDecoder
    private let clock: @Sendable () -> Date

    public init(
        store: any SpotStore,
        transport: any BundleTransport = URLSessionBundleTransport(),
        source: BundleSource = .default,
        decoder: BundleDecoder = BundleDecoder(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.source = source
        self.decoder = decoder
        self.clock = clock
    }

    // MARK: - Index

    /// The city list.
    ///
    /// Stored copy inside the hour, a fetch outside it — and the stored copy
    /// again if that fetch fails, because a stale list of cities is worth far
    /// more in the field than an error.
    public func index(forceRefresh: Bool = false) async throws -> CityIndex {
        let stored = try? await store.storedIndex()
        if !forceRefresh, let stored, let fetchedAt = try? await store.indexFetchedAt(),
           clock().timeIntervalSince(fetchedAt) < Self.indexCacheDuration {
            return stored
        }

        do {
            let data = try await transport.data(from: source.indexURL)
            let index = try decoder.decodeIndex(data)
            try await store.store(index)
            return index
        } catch {
            if let stored { return stored }
            throw BundleRefreshError.indexUnavailable(reason: String(describing: error))
        }
    }

    /// The stored city list without touching the network at all — what the map
    /// uses on a cold launch in airplane mode.
    public func storedIndex() async -> CityIndex? {
        try? await store.storedIndex()
    }

    /// The city a coarse fix falls in, or `nil` when there is no data for it.
    public func city(containing coordinate: Coordinate, forceRefresh: Bool = false) async throws -> CityIndexEntry? {
        try await index(forceRefresh: forceRefresh).city(containing: coordinate)
    }

    // MARK: - Bundles

    /// Downloads a city if the stored copy is missing or older than the index.
    ///
    /// Nothing is deleted before the replacement has been decompressed, verified
    /// against the published SHA-256 and decoded. A failure at any step throws
    /// with the city named and leaves the stored bundle exactly as it was.
    @discardableResult
    public func refresh(cityId: String, forceRefresh: Bool = false) async throws -> BundleRefreshOutcome {
        let index = try await index()
        guard let entry = index.entry(for: cityId) else {
            throw BundleRefreshError.unknownCity(cityId: cityId)
        }
        return try await refresh(entry: entry, forceRefresh: forceRefresh)
    }

    @discardableResult
    public func refresh(entry: CityIndexEntry, forceRefresh: Bool = false) async throws -> BundleRefreshOutcome {
        let storedVersion = try? await store.storedBundleVersion(cityId: entry.cityId)
        if !forceRefresh, !decoder.needsDownload(entry: entry, storedBundleVersion: storedVersion) {
            return .alreadyCurrent(cityId: entry.cityId, bundleVersion: storedVersion ?? entry.bundleVersion)
        }

        let compressed: Data
        do {
            compressed = try await transport.data(from: source.bundleURL(for: entry))
        } catch {
            throw BundleRefreshError.downloadFailed(cityId: entry.cityId, reason: String(describing: error))
        }

        let city: City
        do {
            city = try decoder.decodeCity(compressed: compressed, entry: entry)
        } catch let error as BundleError {
            throw BundleRefreshError.rejected(cityId: entry.cityId, underlying: error)
        } catch {
            throw BundleRefreshError.importFailed(cityId: entry.cityId, reason: String(describing: error))
        }

        do {
            try await store.replaceSpots(for: entry.cityId, with: city)
        } catch {
            throw BundleRefreshError.importFailed(cityId: entry.cityId, reason: String(describing: error))
        }

        return .imported(
            cityId: entry.cityId,
            bundleVersion: city.bundleVersion,
            spotCount: city.spotCount
        )
    }

    /// Whether a city has to be downloaded before it can be drawn.
    public func needsDownload(entry: CityIndexEntry) async -> Bool {
        let storedVersion = try? await store.storedBundleVersion(cityId: entry.cityId)
        return decoder.needsDownload(entry: entry, storedBundleVersion: storedVersion)
    }

    public func removeCity(cityId: String) async throws {
        try await store.removeCity(cityId: cityId)
    }
}
