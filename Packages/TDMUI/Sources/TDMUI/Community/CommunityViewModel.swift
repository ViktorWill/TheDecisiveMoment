import Foundation
import Observation
import TDMCore
import TDMSpots

/// The Community tab's state: the local photographer, their plans, and enough
/// about the cities on the device to file a new one.
///
/// Everything goes through ``TDMCore/CommunityBackend``, never through
/// SwiftData directly, so phase 3's server implementation replaces one value at
/// the composition root — `docs/SPEC-community.md`.
@MainActor
@Observable
public final class CommunityViewModel {
    /// The city a plan belongs to when the device has no bundle and no index to
    /// place it in — on a plane, or before a first download. A session still
    /// needs a city id, and refusing to let someone write a plan down because
    /// they have not downloaded a map yet would be an invented obstacle.
    public static let elsewhereCityId = "elsewhere"

    public private(set) var sessions: [ShootSession] = []
    public private(set) var profile: Photographer?
    /// Names for anchored spots, by spot id. Resolved once per load so a row
    /// can say *Admiralbrücke* rather than `local:9F2…`.
    public private(set) var anchorNames: [String: String] = [:]
    /// Cities the editor can file a plan under: whatever is stored, whatever
    /// the index knows, and *Elsewhere*.
    public private(set) var cities: [CommunityCity] = []
    public private(set) var isLoading = false
    /// Set when a write failed. What is on screen is still what is stored.
    public private(set) var errorMessage: String?

    private let backend: any CommunityBackend
    let store: any SpotStore
    public let location: LocationProvider
    private let clock: @MainActor () -> Date

    public init(
        backend: any CommunityBackend,
        store: any SpotStore = InMemorySpotStore(),
        location: LocationProvider = LocationProvider(),
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.backend = backend
        self.store = store
        self.location = location
        self.clock = clock
    }

    /// A city a plan can be filed under.
    public struct CommunityCity: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        /// `nil` for *Elsewhere*, which is deliberately nowhere.
        public var bbox: BoundingBox?
    }

    // MARK: - Loading

    public func load() async {
        isLoading = sessions.isEmpty
        defer { isLoading = false }
        do {
            profile = try await backend.profile()
            sessions = try await backend.sessions(from: clock())
        } catch {
            errorMessage = Self.message(for: error)
        }
        await resolveAnchorNames()
        await loadCities()
    }

    private func resolveAnchorNames() async {
        var names: [String: String] = [:]
        for id in Set(sessions.compactMap(\.spotId)) {
            // A spot a bundle refresh dropped simply has no name here. The plan
            // is not lost with it.
            if let spot = try? await store.spot(id: id) { names[id] = spot.name }
        }
        anchorNames = names
    }

    private func loadCities() async {
        var byId: [String: CommunityCity] = [:]
        for cityId in (try? await store.storedCityIds()) ?? [] {
            if let summary = try? await store.storedCity(cityId: cityId) {
                byId[cityId] = CommunityCity(id: cityId, name: summary.name, bbox: summary.bbox)
            }
        }
        if let index = try? await store.storedIndex() {
            for entry in index.cities where byId[entry.cityId] == nil {
                byId[entry.cityId] = CommunityCity(id: entry.cityId, name: entry.name, bbox: entry.bbox)
            }
        }
        cities = byId.values.sorted { $0.name < $1.name }
            + [CommunityCity(id: Self.elsewhereCityId, name: "Elsewhere", bbox: nil)]
    }

    // MARK: - Writing

    /// Creates or replaces a plan, then reloads, so the list is what the backend
    /// says rather than what the screen assumed.
    public func save(_ session: ShootSession) async {
        errorMessage = nil
        do {
            if sessions.contains(where: { $0.id == session.id }) {
                _ = try await backend.update(session)
            } else {
                _ = try await backend.create(session)
            }
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func delete(_ session: ShootSession) async {
        errorMessage = nil
        do {
            try await backend.cancel(id: session.id)
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func saveProfile(_ edited: Photographer) async {
        errorMessage = nil
        do {
            profile = try await backend.save(edited)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: - Drafting

    /// A blank plan for tomorrow morning, hosted by the local photographer.
    ///
    /// Tomorrow rather than now: a plan written at 21:00 for 21:00 would be over
    /// before it was saved, and the list only shows what has not finished.
    public func newSession(anchoredTo spot: Spot? = nil) -> ShootSession? {
        guard let profile else { return nil }
        let city = spot.flatMap { cityId(containing: $0.coordinate) } ?? defaultCityId
        return ShootSession(
            cityId: city,
            spotId: spot?.id,
            title: spot?.name ?? "",
            startsAt: Self.nextMorning(after: clock()),
            duration: 2 * 3600,
            meetingPoint: spot?.coordinate ?? startingCoordinate(for: city),
            hostId: profile.id,
            visibility: .private
        )
    }

    /// 09:00 tomorrow, in the device's calendar.
    static func nextMorning(after moment: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: moment) ?? moment
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Where a new plan lands: the city the user is standing in, else the first
    /// city on the device, else *Elsewhere*.
    public var defaultCityId: String {
        if !location.isUsingFallback, let here = cityId(containing: location.coordinate) {
            return here
        }
        return cities.first?.id ?? Self.elsewhereCityId
    }

    func cityId(containing coordinate: Coordinate) -> String? {
        cities.first { $0.bbox?.contains(coordinate) == true }?.id
    }

    /// The meeting point a fresh plan starts from: the fix when there is one,
    /// otherwise the middle of the city, which is a better guess than Times
    /// Square in Berlin.
    func startingCoordinate(for cityId: String) -> Coordinate {
        if location.isUsingFallback,
           let bbox = cities.first(where: { $0.id == cityId })?.bbox {
            return bbox.center
        }
        return location.coordinate
    }

    public func name(forAnchor spotId: String?) -> String? {
        spotId.flatMap { anchorNames[$0] }
    }

    public func cityName(_ cityId: String) -> String {
        cities.first { $0.id == cityId }?.name ?? cityId
    }

    private static func message(for error: Error) -> String {
        switch error {
        case CommunityError.invalidSession:
            "That plan is missing something — it needs a title and a length."
        case CommunityError.invalidProfile:
            "A name cannot be blank."
        case CommunityError.sessionNotFound:
            "That plan is no longer on this device."
        case let CommunityError.storageFailed(description):
            "Could not save to this device. \(description)"
        default:
            String(describing: error)
        }
    }
}
