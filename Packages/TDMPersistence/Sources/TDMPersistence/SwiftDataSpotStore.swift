#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore
import TDMSpots

/// The SwiftData implementation of ``TDMSpots/SpotStore``.
///
/// A model actor rather than a main-actor store: the map queries on every region
/// change, and a bounding-box fetch of a dense district has no business running
/// where the map is being drawn. Everything crossing the boundary is a `TDMCore`
/// value type — the `@Model` classes never leave.
@ModelActor
public actor SwiftDataSpotStore: SpotStore {
    /// The models this store owns. The app passes these to its container.
    public static var models: [any PersistentModel.Type] {
        [StoredCityBundle.self, StoredSpot.self, StoredPin.self, StoredCityIndex.self]
    }

    /// A store over a container. Declared here rather than left to the macro's
    /// generated initialiser, so callers outside this package do not depend on
    /// the access level `@ModelActor` happens to give it.
    public static func make(container: ModelContainer) -> SwiftDataSpotStore {
        SwiftDataSpotStore(modelContainer: container)
    }

    /// A container for the spot models. `inMemory` is for previews and tests.
    ///
    /// `"spots"`: this app also has a gear store and a community store, each
    /// with their own container — see `ModelStoreLocation`.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: try ModelStoreLocation.url(named: "spots"))
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }

    // MARK: - Index

    public func storedIndex() throws -> CityIndex? {
        guard let row = try indexRow() else { return nil }
        return try? BundleCoding.decoder().decode(CityIndex.self, from: row.data)
    }

    public func store(_ index: CityIndex) throws {
        let data = try BundleCoding.encoder().encode(index)
        if let row = try indexRow() {
            row.data = data
            row.fetchedAt = Date()
        } else {
            modelContext.insert(StoredCityIndex(data: data, fetchedAt: Date()))
        }
        try modelContext.save()
    }

    public func indexFetchedAt() throws -> Date? {
        try indexRow()?.fetchedAt
    }

    private func indexRow() throws -> StoredCityIndex? {
        try modelContext.fetch(FetchDescriptor<StoredCityIndex>()).first
    }

    // MARK: - Bundles

    public func storedBundleVersion(cityId: String) throws -> Int? {
        try bundleRow(cityId: cityId)?.bundleVersion
    }

    public func storedCityIds() throws -> [String] {
        try modelContext
            .fetch(FetchDescriptor<StoredCityBundle>(sortBy: [SortDescriptor(\.name)]))
            .map(\.cityId)
    }

    public func storedCity(cityId: String) throws -> StoredCitySummary? {
        try bundleRow(cityId: cityId)?.summary
    }

    /// Replaces a city's spots in one transaction.
    ///
    /// The previous rows go first and the new ones are inserted before the
    /// single save, so a throw part-way leaves the context unsaved and the
    /// stored bundle exactly as it was. Half of two bundles would be a map that
    /// is quietly missing streets, which is indistinguishable in the field from
    /// those streets not existing.
    public func replaceSpots(for cityId: String, with city: City) throws {
        guard city.cityId == cityId else {
            throw SpotStoreError.underlying(
                description: "bundle for \(city.cityId) cannot replace \(cityId)"
            )
        }
        do {
            try modelContext.delete(model: StoredSpot.self, where: #Predicate { $0.cityId == cityId })
            for spot in city.spots where spot.isValid {
                modelContext.insert(StoredSpot(spot, cityId: cityId))
            }
            if let existing = try bundleRow(cityId: cityId) {
                existing.apply(city)
            } else {
                modelContext.insert(StoredCityBundle(city))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw SpotStoreError.underlying(description: String(describing: error))
        }
    }

    public func removeCity(cityId: String) throws {
        try modelContext.delete(model: StoredSpot.self, where: #Predicate { $0.cityId == cityId })
        try modelContext.delete(model: StoredCityBundle.self, where: #Predicate { $0.cityId == cityId })
        try modelContext.save()
    }

    // MARK: - Reading

    /// The city's spots and the user's pins in one answer.
    ///
    /// Only the bounding box and the score floor reach the store; the rest of
    /// the query — kinds, openness, source, search, *lit now* — is applied to
    /// the region's rows in memory, where it is a few hundred comparisons.
    public func spots(in cityId: String, matching query: SpotQuery) throws -> [Spot] {
        let box = query.boundingBox
        let minLat = box?.minLat ?? -90
        let maxLat = box?.maxLat ?? 90
        let minLon = box?.minLon ?? -180
        let maxLon = box?.maxLon ?? 180
        let floor = query.minimumScore

        let descriptor = FetchDescriptor<StoredSpot>(
            predicate: #Predicate {
                $0.cityId == cityId
                    && $0.lat >= minLat && $0.lat <= maxLat
                    && $0.lon >= minLon && $0.lon <= maxLon
                    && ($0.score >= floor || $0.curated)
            }
        )
        let bundled = try modelContext.fetch(descriptor).map(\.value)

        let pinDescriptor = FetchDescriptor<StoredPin>(
            predicate: #Predicate {
                $0.lat >= minLat && $0.lat <= maxLat && $0.lon >= minLon && $0.lon <= maxLon
            }
        )
        let pins = try modelContext.fetch(pinDescriptor).map(\.value)

        return SpotFilter.apply(query, to: bundled + pins)
    }

    public func spot(id: String) throws -> Spot? {
        if LocalPin.isLocal(id: id) {
            return try pinRow(id: id)?.value
        }
        let descriptor = FetchDescriptor<StoredSpot>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.value
    }

    // MARK: - Pins

    public func upsertPin(_ spot: Spot) throws {
        guard LocalPin.isLocal(id: spot.id) else {
            throw SpotStoreError.notALocalPin(id: spot.id)
        }
        if let existing = try pinRow(id: spot.id) {
            existing.apply(spot)
        } else {
            modelContext.insert(StoredPin(spot))
        }
        try modelContext.save()
    }

    public func removePin(id: String) throws {
        guard LocalPin.isLocal(id: id) else {
            throw SpotStoreError.notALocalPin(id: id)
        }
        try modelContext.delete(model: StoredPin.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    /// Every pin, newest first — the order the export and the settings list want.
    public func pins() throws -> [Spot] {
        try modelContext
            .fetch(FetchDescriptor<StoredPin>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .map(\.value)
    }

    // MARK: - Support

    private func bundleRow(cityId: String) throws -> StoredCityBundle? {
        let descriptor = FetchDescriptor<StoredCityBundle>(predicate: #Predicate { $0.cityId == cityId })
        return try modelContext.fetch(descriptor).first
    }

    private func pinRow(id: String) throws -> StoredPin? {
        let descriptor = FetchDescriptor<StoredPin>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }
}
#endif
