import Foundation
import TDMCore

/// Storage for decoded bundles and the user's own pins.
///
/// The interface `TDMPersistence` implements with SwiftData. It is declared
/// here, next to the code that decodes and filters, so that `TDMSpots` can be
/// exercised against an in-memory double and stays free of any framework.
///
/// Spots are stored as rows rather than as one blob per city, because the map
/// queries a visible rectangle and must not load a city to draw a street.
public protocol SpotStore: Sendable {
    /// The index as last fetched, or `nil` when nothing has been stored yet.
    func storedIndex() async throws -> CityIndex?
    func store(_ index: CityIndex) async throws
    /// When the index last arrived, which is what the one-hour cache of
    /// `docs/DATA-BUNDLES.md` is measured against. `nil` when none is stored.
    func indexFetchedAt() async throws -> Date?

    /// The stored bundle version for a city, or `nil` when it is not stored.
    /// The client re-downloads only when this is lower than the index's.
    func storedBundleVersion(cityId: String) async throws -> Int?

    /// Replace a city's spots. Atomic: a failed import must leave the previous
    /// bundle intact rather than half of two cities.
    func replaceSpots(for cityId: String, with city: City) async throws

    /// Every stored city id, for the picker's download state.
    func storedCityIds() async throws -> [String]

    /// What is known about a stored city without loading its spots: the city
    /// chip's count, and the attribution the map surface has to show.
    func storedCity(cityId: String) async throws -> StoredCitySummary?

    /// Remove a city's spots and its stored version.
    func removeCity(cityId: String) async throws

    /// The user's own pins and the stored bundle, filtered together —
    /// own pins are included in filters and search, and are never removed by a
    /// bundle refresh.
    func spots(in cityId: String, matching query: SpotQuery) async throws -> [Spot]

    /// One spot by id, whether it came from a bundle or a long-press.
    func spot(id: String) async throws -> Spot?

    /// Create or update a local pin. Ids are `local:{uuid}` and are never
    /// uploaded in v1.
    func upsertPin(_ spot: Spot) async throws
    func removePin(id: String) async throws
    func pins() async throws -> [Spot]
}

/// A stored bundle's header: everything the map needs before it draws a single
/// spot, and nothing that requires reading the city.
public struct StoredCitySummary: Sendable, Hashable, Identifiable {
    public var cityId: String
    public var name: String
    public var country: String
    public var spotCount: Int
    public var bundleVersion: Int
    /// When the pipeline generated the bundle.
    public var generatedAt: Date
    /// When this device imported it.
    public var importedAt: Date
    public var bbox: BoundingBox
    /// Displayed, not merely stored — `docs/DATA-BUNDLES.md` ("Attribution").
    public var attribution: Attribution
    public var scoreFloor: Double?

    public var id: String { cityId }

    public init(
        cityId: String,
        name: String,
        country: String,
        spotCount: Int,
        bundleVersion: Int,
        generatedAt: Date,
        importedAt: Date,
        bbox: BoundingBox,
        attribution: Attribution,
        scoreFloor: Double? = nil
    ) {
        self.cityId = cityId
        self.name = name
        self.country = country
        self.spotCount = spotCount
        self.bundleVersion = bundleVersion
        self.generatedAt = generatedAt
        self.importedAt = importedAt
        self.bbox = bbox
        self.attribution = attribution
        self.scoreFloor = scoreFloor
    }
}

/// What can go wrong in storage, in terms the UI can act on.
public enum SpotStoreError: Error, Equatable, Sendable {
    /// The bundle is not stored, so the map has only the user's pins to draw.
    case cityNotStored(cityId: String)
    /// A pin id that is not `local:{uuid}`. Bundle spots are read-only: editing
    /// one would be silently undone by the next refresh.
    case notALocalPin(id: String)
    case underlying(description: String)
}
