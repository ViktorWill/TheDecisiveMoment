import Foundation
import TDMCore
import TDMSpots

/// What the filter pills add up to, persisted between launches
/// (`docs/SPEC-map.md`, "Filters").
///
/// Kept apart from ``SpotQuery`` because a query also carries the visible
/// rectangle and the sun, which are facts about *now* rather than choices the
/// user made and expects to find again.
struct MapFilters: Codable, Hashable, Sendable {
    /// The floor the design shows on the pill, and the spec's default.
    static let defaultMinimumScore = 0.3

    var kinds: Set<SpotKind> = []
    var openness: Set<Openness> = []
    var sources: Set<SpotSource> = []
    var minimumScore: Double = defaultMinimumScore
    /// The pill that will actually get used.
    var litNow = false

    var isDefault: Bool {
        kinds.isEmpty && openness.isEmpty && sources.isEmpty && !litNow
            && minimumScore == Self.defaultMinimumScore
    }

    /// The query for a region. `sunlight` is passed in already solved, once per
    /// refresh, so the per-spot cost of *lit now* stays arithmetic.
    func query(
        boundingBox: BoundingBox?,
        searchText: String,
        sunlight: SunFilter?
    ) -> SpotQuery {
        SpotQuery(
            boundingBox: boundingBox,
            kinds: kinds,
            openness: openness,
            sources: sources,
            minimumScore: minimumScore,
            searchText: searchText,
            // A curated entry below the floor is still the entry someone wrote
            // by hand, and hiding it is never what the slider meant.
            alwaysIncludeCurated: true,
            sunlight: litNow ? sunlight : nil
        )
    }

    mutating func toggle(kind: SpotKind) {
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
    }

    mutating func toggle(openness value: Openness) {
        if openness.contains(value) { openness.remove(value) } else { openness.insert(value) }
    }

    mutating func toggle(source: SpotSource) {
        if sources.contains(source) { sources.remove(source) } else { sources.insert(source) }
    }
}

/// Where the filters live between launches. `UserDefaults` rather than SwiftData:
/// this is a preference, not data, and losing it costs a tap.
struct MapFilterStore {
    static let key = "map.filters.v1"

    // `UserDefaults` is thread-safe by documented contract but predates
    // `Sendable`; `nonisolated(unsafe)` records that the runtime guarantee,
    // not a missing check, is what makes this safe.
    nonisolated(unsafe) var defaults: UserDefaults = .standard

    func load() -> MapFilters {
        guard let data = defaults.data(forKey: Self.key),
              let filters = try? JSONDecoder().decode(MapFilters.self, from: data)
        else { return MapFilters() }
        return filters
    }

    func save(_ filters: MapFilters) {
        guard let data = try? JSONEncoder().encode(filters) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
