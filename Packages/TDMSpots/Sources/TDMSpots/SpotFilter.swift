import Foundation
import TDMCore

/// What the map's filter pills and search field add up to,
/// `docs/SPEC-map.md` ("Filters").
///
/// Empty sets mean "no constraint" rather than "match nothing", so a default
/// query returns the city.
public struct SpotQuery: Sendable, Hashable {
    /// Visible rectangle. The map queries by region, never by whole city.
    public var boundingBox: BoundingBox?
    public var kinds: Set<SpotKind>
    public var openness: Set<Openness>
    /// A spot matches when it carries *any* of these sources — "curated only"
    /// is `[.curated]`, "include generated" is empty, "my pins" is `[.local]`.
    public var sources: Set<SpotSource>
    /// Default 0.3 in the UI. Kept explicit here so the map can raise it when a
    /// region holds more than it will draw.
    public var minimumScore: Double
    /// Plain substring match over `name` and `tags`. Offline, no network.
    public var searchText: String
    /// Curated spots are never dropped by a filter that only wanted the good
    /// stuff — they *are* the good stuff.
    public var alwaysIncludeCurated: Bool
    /// The *lit now* pill: the sun as it is at this instant, or `nil` for no
    /// constraint. The caller computes it once per refresh from `TDMLight`;
    /// see ``SunFilter``.
    public var sunlight: SunFilter?

    public init(
        boundingBox: BoundingBox? = nil,
        kinds: Set<SpotKind> = [],
        openness: Set<Openness> = [],
        sources: Set<SpotSource> = [],
        minimumScore: Double = 0,
        searchText: String = "",
        alwaysIncludeCurated: Bool = false,
        sunlight: SunFilter? = nil
    ) {
        self.boundingBox = boundingBox
        self.kinds = kinds
        self.openness = openness
        self.sources = sources
        self.minimumScore = minimumScore
        self.searchText = searchText
        self.alwaysIncludeCurated = alwaysIncludeCurated
        self.sunlight = sunlight
    }
}

/// Filtering, searching and ranking over an already-decoded set of spots.
public enum SpotFilter {
    /// The spots matching `query`, highest score first.
    ///
    /// Ties break on id so a redraw of the same region never reshuffles the
    /// list under the user's thumb.
    public static func apply(_ query: SpotQuery, to spots: [Spot]) -> [Spot] {
        spots
            .filter { matches(query, $0) }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
            }
    }

    public static func matches(_ query: SpotQuery, _ spot: Spot) -> Bool {
        if let boundingBox = query.boundingBox, !boundingBox.contains(spot.coordinate) { return false }
        if !query.kinds.isEmpty && !query.kinds.contains(spot.kind) { return false }
        if !query.openness.isEmpty && !query.openness.contains(spot.openness) { return false }
        if !query.sources.isEmpty && query.sources.isDisjoint(with: spot.sources) { return false }
        if !matchesSearch(query.searchText, spot) { return false }
        // Shade is a fact about the place, not a measure of it: a curated spot
        // standing in shadow is still in shadow, so this one is not waived.
        if let sunlight = query.sunlight, !sunlight.isLit(spot) { return false }

        // The score floor is the one filter curation overrides: a hand-written
        // entry that scored low is still the entry someone chose to write.
        if spot.score < query.minimumScore {
            return query.alwaysIncludeCurated && spot.curated
        }
        return true
    }

    /// Substring match over name and tags, diacritic- and case-insensitive so
    /// that typing "cafe" finds "Café".
    static func matchesSearch(_ text: String, _ spot: Spot) -> Bool {
        let needle = fold(text)
        guard !needle.isEmpty else { return true }
        if fold(spot.name).contains(needle) { return true }
        return spot.tags.contains { fold($0).contains(needle) }
    }

    private static func fold(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }
}
