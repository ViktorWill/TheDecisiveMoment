import Foundation
import Observation
import TDMCore
import TDMLight
import TDMPersistence
import TDMSpots
import TDMWeather

/// The Map tab's state: where the user is, which city that is, what is in the
/// visible rectangle, and what the filters have left of it.
///
/// The rules that decide what a user sees — clustering, the annotation budget,
/// *lit now* — live in `TDMSpots` and are tested there. This type gathers
/// inputs, keeps the store at arm's length, and never lets a network failure
/// cost the photographer the map: if a bundle is stored, the map draws from it
/// before anything is asked of the network, and there is no spinner in that
/// path (`docs/SPEC-map.md`, "Offline behaviour").
@MainActor
@Observable
public final class MapViewModel {
    /// A region change is a stream, not an event: the map is redrawn once the
    /// thumb settles, `docs/SPEC-map.md` ("Performance").
    public static let regionDebounceSeconds = 0.150

    /// The rectangle the list falls back to when the map has not reported one
    /// yet — roughly a 20-minute walk in each direction.
    static let initialSpanMetres = 2_000.0

    // MARK: Inputs

    public var searchText = "" {
        didSet { if searchText != oldValue { scheduleRefresh() } }
    }

    /// The sun overlay toggle on the map surface.
    public var isSunOverlayVisible = false

    var filters: MapFilters {
        didSet {
            guard filters != oldValue else { return }
            filterStore.save(filters)
            scheduleRefresh()
        }
    }

    // MARK: State

    /// The city whose bundle is stored and being drawn, `nil` when none is.
    public private(set) var city: StoredCitySummary?
    /// The index entry for where the user is, whether or not it is stored. This
    /// is what the download prompt names.
    public private(set) var indexEntry: CityIndexEntry?
    public private(set) var annotations = MapAnnotations(
        clusters: [], effectiveMinimumScore: 0, matchingSpotCount: 0, isLimited: false
    )
    /// The ranked list under the map, nearest-first within the visible region.
    public private(set) var listSpots: [Spot] = []
    /// The sun as it is now at the centre of the region: the *lit now* filter
    /// and the overlay both read this, and it is solved once per refresh.
    public private(set) var sun: SolarPosition?
    public private(set) var isDownloading = false
    /// Set when a refresh failed, naming the city that failed. The previous
    /// bundle is still on screen.
    public private(set) var refreshError: String?
    /// Cities offered by the index, for the picker.
    public private(set) var indexCities: [CityIndexEntry] = []
    public private(set) var storedCityIds: Set<String> = []
    public private(set) var pins: [Spot] = []
    /// The gear the *light right now* strip solves for. The shipped catalogue
    /// stands in when the store is empty or broken, exactly as on the Light tab.
    public private(set) var gearProfile: GearProfile?

    // MARK: Dependencies

    let store: any SpotStore
    private let bundles: BundleService?
    private let gearStore: GearStore?
    /// `nil` leaves the light strip on its clear-sky fallback, which it labels.
    let weather: WeatherService?
    public let location: LocationProvider
    public let heading: HeadingProvider
    /// Not an initialiser parameter: `MapFilterStore` is internal, and a public
    /// initialiser cannot name it.
    private let filterStore = MapFilterStore()
    private let clock: @MainActor () -> Date

    @ObservationIgnored private var region: BoundingBox?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoadedOnce = false

    public init(
        store: any SpotStore,
        bundles: BundleService? = nil,
        gearStore: GearStore? = nil,
        weather: WeatherService? = nil,
        location: LocationProvider = LocationProvider(),
        heading: HeadingProvider = HeadingProvider(),
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.bundles = bundles
        self.gearStore = gearStore
        self.weather = weather
        self.location = location
        self.heading = heading
        self.clock = clock
        // A fresh reader: `self` is not available until every property is set.
        self.filters = MapFilterStore().load()
    }

    // MARK: Derived

    public var coordinate: Coordinate { location.coordinate }

    /// The centre the list measures distance from: the user, always — a list
    /// that reordered itself as the map panned would be unusable while walking.
    public var listOrigin: Coordinate { coordinate }

    /// What the city chip says: `New York City · 842 spots · offline`.
    public var cityChipTitle: String? { city?.name ?? indexEntry?.name }
    public var cityChipCount: Int? { city?.spotCount ?? indexEntry?.spotCount }
    /// The bundle is on the device, so the map works with the radio off.
    public var isCityStored: Bool { city != nil }

    /// The line under the pills when the region held more than the map draws.
    ///
    /// Markers that vanish without explanation read as missing data, so the
    /// raised floor is stated (`docs/SPEC-map.md`, "Performance").
    public var annotationLimitNote: String? {
        guard annotations.isLimited else { return nil }
        let floor = String(format: "%.2f", annotations.effectiveMinimumScore)
        return "\(annotations.matchingSpotCount) spots here — showing the strongest \(annotations.clusters.reduce(0) { $0 + $1.count }), score \(floor) and above. Zoom in for the rest."
    }

    /// The prompt for a city that is in the index but not on the device:
    /// *"New York City — 842 spots, 180 KB. Download."*
    public var downloadPrompt: String? {
        guard let indexEntry, city?.cityId != indexEntry.cityId else { return nil }
        return "\(indexEntry.name) — \(indexEntry.spotCount) spots, \(Self.byteCount(indexEntry.bytes)). Download."
    }

    /// Said plainly when the index has nothing for where the user is standing.
    public var emptyAreaNote: String? {
        guard city == nil, indexEntry == nil, !indexCities.isEmpty || hasLoadedOnce else { return nil }
        return "No spot data for this area yet"
    }

    /// The attribution the map surface must show. Not optional, and not buried
    /// in a settings screen (`docs/DATA-BUNDLES.md`, "Attribution").
    public var attributionLines: [String] {
        let lines = city?.attribution.displayLines ?? []
        return lines.isEmpty ? ["© OpenStreetMap contributors"] : lines
    }

    static func byteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: Lifecycle

    /// Draws whatever is already stored, then — and only then — asks the
    /// network whether there is anything newer.
    public func start() async {
        location.onCoordinateChange = { [weak self] _ in
            guard let self else { return }
            self.scheduleRefresh()
            Task { await self.resolveCity() }
        }
        location.start()
        heading.start()
        loadGear()
        await loadStored()
        await refresh()
        await resolveCity()
    }

    /// The selected profile, or the catalogue's first. A broken store must not
    /// cost the photographer the strip.
    private func loadGear() {
        if let gearStore {
            try? gearStore.seedIfEmpty()
            let selected = (try? gearStore.selectedProfile()) ?? nil
            let stored = (try? gearStore.profiles()) ?? []
            gearProfile = selected ?? stored.first
        }
        if gearProfile == nil { gearProfile = GearCatalogue.profiles.first }
    }

    /// Everything that can be answered from the device.
    func loadStored() async {
        do {
            let ids = try await store.storedCityIds()
            storedCityIds = Set(ids)
            pins = try await store.pins()
            if let index = try await store.storedIndex() {
                indexCities = index.citiesSortedByDistance(from: coordinate)
                indexEntry = index.city(containing: coordinate)
            }
            await adoptStoredCity()
            hasLoadedOnce = true
        } catch {
            refreshError = "Stored spots could not be read."
        }
    }

    /// Picks the stored bundle for where the user is: the one whose city
    /// contains the coordinate, or — failing that — the nearest stored city, so
    /// that a trip downloaded on the sofa is still on screen in the street.
    private func adoptStoredCity() async {
        let candidates: [String]
        if let entry = indexEntry, storedCityIds.contains(entry.cityId) {
            candidates = [entry.cityId]
        } else {
            candidates = storedCityIds.sorted()
        }
        var best: StoredCitySummary?
        for id in candidates {
            guard let summary = try? await store.storedCity(cityId: id) else { continue }
            if summary.bbox.contains(coordinate) {
                best = summary
                break
            }
            if best == nil { best = summary }
        }
        city = best
    }

    /// Asks the index which city this is, and whether its bundle is current.
    /// Failures are silent here: the map is already drawn.
    func resolveCity() async {
        guard let bundles else { return }
        // Offline is the normal case here, not an error worth a banner: the
        // index simply stays at whatever was last stored.
        if let index = try? await bundles.index() {
            indexCities = index.citiesSortedByDistance(from: coordinate)
            indexEntry = index.city(containing: coordinate)
        }
        await loadStoredIds()
        await adoptStoredCity()
    }

    private func loadStoredIds() async {
        if let ids = try? await store.storedCityIds() { storedCityIds = Set(ids) }
    }

    // MARK: Region

    /// The map reports its rectangle continuously; the store is asked once the
    /// thumb settles.
    public func regionChanged(to box: BoundingBox) {
        region = box
        scheduleRefresh()
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Self.regionDebounceSeconds))
            if Task.isCancelled { return }
            await self.refresh()
        }
    }

    /// One query, one clustering pass, one list.
    public func refresh() async {
        let box = region ?? Self.box(around: coordinate, spanMetres: Self.initialSpanMetres)
        let position = Solar.position(
            date: clock(),
            latitudeDegrees: box.center.latitude,
            longitudeDegrees: box.center.longitude
        )
        sun = position
        let sunFilter = SunFilter(
            azimuthDegrees: position.azimuthDegrees,
            elevationDegrees: position.elevationDegrees
        )
        let query = filters.query(boundingBox: box, searchText: searchText, sunlight: sunFilter)

        do {
            let matching = try await store.spots(in: city?.cityId ?? "", matching: query)
            annotations = SpotClusterer.annotations(
                for: matching,
                in: box,
                requestedMinimumScore: filters.minimumScore
            )
            let origin = listOrigin
            listSpots = Array(
                matching
                    .sorted { origin.distance(to: $0.coordinate) < origin.distance(to: $1.coordinate) }
                    .prefix(100)
            )
        } catch {
            refreshError = "Stored spots could not be read."
        }
    }

    // MARK: Downloading

    /// Downloads a city and redraws. The previous bundle stays on screen — and
    /// stays stored — if anything goes wrong.
    public func download(_ entry: CityIndexEntry) async {
        guard let bundles else { return }
        isDownloading = true
        refreshError = nil
        defer { isDownloading = false }
        do {
            _ = try await bundles.refresh(entry: entry)
            await loadStoredIds()
            if let summary = try? await store.storedCity(cityId: entry.cityId) {
                city = summary
            }
            await refresh()
        } catch let error as BundleRefreshError {
            refreshError = error.description
        } catch {
            refreshError = "\(entry.name) could not be updated."
        }
    }

    /// Draws a city the user picked in the picker, downloading it first if it
    /// is not on the device.
    public func select(_ entry: CityIndexEntry) async {
        indexEntry = entry
        if storedCityIds.contains(entry.cityId) {
            city = try? await store.storedCity(cityId: entry.cityId)
            await refresh()
        } else {
            await download(entry)
        }
    }

    public func removeStoredCity(_ entry: CityIndexEntry) async {
        try? await store.removeCity(cityId: entry.cityId)
        await loadStoredIds()
        if city?.cityId == entry.cityId { city = nil }
        await refresh()
    }

    public func dismissError() { refreshError = nil }

    // MARK: Pins

    /// The bearing a dropped pin starts with, when the compass is settled.
    public var pinBearingDegrees: Double? {
        heading.usableHeadingDegrees.map(LocalPin.normalisedAxisBearing)
    }

    /// Saves a pin and redraws. Pins are local to the device in v1 and are never
    /// touched by a bundle refresh.
    public func savePin(_ pin: Spot) async {
        do {
            try await store.upsertPin(pin)
            pins = try await store.pins()
            await refresh()
        } catch {
            refreshError = "That pin could not be saved."
        }
    }

    public func deletePin(id: String) async {
        do {
            try await store.removePin(id: id)
            pins = try await store.pins()
            await refresh()
        } catch {
            refreshError = "That pin could not be removed."
        }
    }

    /// The user's pins as GeoJSON, so the data is never trapped
    /// (`docs/SPEC-map.md`, "Your own pins").
    public func exportPins() async throws -> Data {
        let own = try await store.pins()
        return try GeoJSONExport.featureCollection(own)
    }

    public func spot(id: String) async -> Spot? {
        try? await store.spot(id: id)
    }

    // MARK: Geometry

    /// A box of roughly `spanMetres` across, centred on a coordinate. Used
    /// before the map has reported a rectangle of its own.
    static func box(around centre: Coordinate, spanMetres: Double) -> BoundingBox {
        let metresPerDegreeLatitude = 111_320.0
        let halfLat = (spanMetres / 2) / metresPerDegreeLatitude
        let cosine = max(cos(centre.latitude * .pi / 180), 0.01)
        let halfLon = halfLat / cosine
        return BoundingBox(
            minLat: centre.latitude - halfLat,
            minLon: centre.longitude - halfLon,
            maxLat: centre.latitude + halfLat,
            maxLon: centre.longitude + halfLon
        )
    }
}
