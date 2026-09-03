import Foundation
import TDMCore
import TDMSpots

/// A ``TDMSpots/SpotStore`` that keeps everything in memory.
///
/// Two jobs: it is what SwiftUI previews and the Linux test suite run against,
/// and it is the fallback when the on-disk store will not open — a broken store
/// must cost the user their cache, not the screen.
public actor InMemorySpotStore: SpotStore {
    private var index: CityIndex?
    private var indexTimestamp: Date?
    private var cities: [String: City] = [:]
    private var spotsByCity: [String: [Spot]] = [:]
    private var localPins: [String: Spot] = [:]
    /// Insertion order, so pins come back newest-first as they do from
    /// SwiftData — a difference here would let a test pass against the double
    /// and fail on the device.
    private var pinOrder: [String: Int] = [:]
    private var nextPinOrder = 0
    private var importedAt: [String: Date] = [:]
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    public func storedIndex() -> CityIndex? { index }

    public func store(_ index: CityIndex) {
        self.index = index
        indexTimestamp = clock()
    }

    public func indexFetchedAt() -> Date? { indexTimestamp }

    public func storedBundleVersion(cityId: String) -> Int? {
        cities[cityId]?.bundleVersion
    }

    public func replaceSpots(for cityId: String, with city: City) throws {
        guard city.cityId == cityId else {
            throw SpotStoreError.underlying(description: "bundle for \(city.cityId) cannot replace \(cityId)")
        }
        cities[cityId] = city
        spotsByCity[cityId] = city.spots.filter(\.isValid)
        importedAt[cityId] = clock()
    }

    public func storedCityIds() -> [String] {
        cities.keys.sorted()
    }

    public func storedCity(cityId: String) -> StoredCitySummary? {
        guard let city = cities[cityId] else { return nil }
        return StoredCitySummary(
            cityId: city.cityId,
            name: city.name,
            country: city.country,
            spotCount: spotsByCity[cityId]?.count ?? 0,
            bundleVersion: city.bundleVersion,
            generatedAt: city.generatedAt,
            importedAt: importedAt[cityId] ?? city.generatedAt,
            bbox: city.bbox,
            attribution: city.attribution,
            scoreFloor: city.scoreFloor
        )
    }

    public func removeCity(cityId: String) {
        cities[cityId] = nil
        spotsByCity[cityId] = nil
        importedAt[cityId] = nil
    }

    public func spots(in cityId: String, matching query: SpotQuery) -> [Spot] {
        SpotFilter.apply(query, to: (spotsByCity[cityId] ?? []) + Array(localPins.values))
    }

    public func spot(id: String) -> Spot? {
        if let pin = localPins[id] { return pin }
        for spots in spotsByCity.values {
            if let spot = spots.first(where: { $0.id == id }) { return spot }
        }
        return nil
    }

    public func upsertPin(_ spot: Spot) throws {
        guard LocalPin.isLocal(id: spot.id) else { throw SpotStoreError.notALocalPin(id: spot.id) }
        localPins[spot.id] = spot
        if pinOrder[spot.id] == nil {
            pinOrder[spot.id] = nextPinOrder
            nextPinOrder += 1
        }
    }

    public func removePin(id: String) throws {
        guard LocalPin.isLocal(id: id) else { throw SpotStoreError.notALocalPin(id: id) }
        localPins[id] = nil
        pinOrder[id] = nil
    }

    public func pins() -> [Spot] {
        localPins.values.sorted { (pinOrder[$0.id] ?? 0) > (pinOrder[$1.id] ?? 0) }
    }
}
