import Foundation
import TDMCore

/// One marker on the map: either a single spot or a bubble standing for several.
///
/// Clusters carry their highest-scoring member, because the bubble adopts that
/// spot's colour — `docs/SPEC-map.md` ("Annotations") — and because tapping one
/// should zoom to something worth arriving at.
public struct SpotCluster: Sendable, Hashable, Identifiable {
    /// Stable for a given set of members, so SwiftUI does not re-insert every
    /// annotation when the region is nudged.
    public var id: String
    public var coordinate: Coordinate
    /// Highest-scoring member: the bubble's colour and its label come from it.
    public var representative: Spot
    public var count: Int
    /// Every member, highest score first. A single-spot annotation has one.
    public var spots: [Spot]

    public init(coordinate: Coordinate, spots: [Spot]) {
        let ordered = spots.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        self.coordinate = coordinate
        self.spots = ordered
        self.representative = ordered[0]
        self.count = ordered.count
        self.id = ordered.count == 1 ? ordered[0].id : "cluster:\(ordered[0].id):\(ordered.count)"
    }

    public var isSingle: Bool { count == 1 }
    public var containsCurated: Bool { spots.contains(where: \.curated) }
}

/// What the map should draw for one region, and what it had to leave out.
public struct MapAnnotations: Sendable, Hashable {
    public var clusters: [SpotCluster]
    /// The floor actually applied. Higher than the user's when the region held
    /// more spots than the map will draw.
    public var effectiveMinimumScore: Double
    /// How many spots matched before the cap.
    public var matchingSpotCount: Int
    /// Whether the cap raised the floor. The UI says so: a marker that vanished
    /// without explanation reads as missing data.
    public var isLimited: Bool

    public init(
        clusters: [SpotCluster],
        effectiveMinimumScore: Double,
        matchingSpotCount: Int,
        isLimited: Bool
    ) {
        self.clusters = clusters
        self.effectiveMinimumScore = effectiveMinimumScore
        self.matchingSpotCount = matchingSpotCount
        self.isLimited = isLimited
    }
}

/// Grid clustering and the annotation budget of `docs/SPEC-map.md`
/// ("Performance").
///
/// Pure, so the two rules that decide what a user sees — when spots merge into
/// bubbles, and what happens when a region holds more than the map will draw —
/// are testable without a simulator.
public enum SpotClusterer {
    /// Individual spots below this visible span, bubbles above it.
    public static let clusteringSpanMetres = 2_000.0
    /// The most annotations the map draws at once.
    public static let maximumAnnotations = 300
    /// Cluster cells across the visible width. Twelve gives bubbles roughly a
    /// thumb apart on a 393 pt screen.
    public static let clusterColumns = 12.0

    /// The markers for a region, capped.
    ///
    /// - Parameters:
    ///   - spots: Already filtered to the region by the store's bounding-box
    ///     query — this function never sees a whole city.
    ///   - region: The visible rectangle.
    ///   - requestedMinimumScore: The floor the user set, reported back when
    ///     nothing forced it higher.
    public static func annotations(
        for spots: [Spot],
        in region: BoundingBox,
        requestedMinimumScore: Double = 0,
        limit: Int = maximumAnnotations
    ) -> MapAnnotations {
        let ranked = spots.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        let (kept, floor, isLimited) = capped(ranked, requestedMinimumScore: requestedMinimumScore, limit: limit)

        let clusters = visibleSpanMetres(of: region) > clusteringSpanMetres
            ? cluster(kept, in: region)
            : kept.map { SpotCluster(coordinate: $0.coordinate, spots: [$0]) }

        return MapAnnotations(
            clusters: drawingOrder(clusters),
            effectiveMinimumScore: floor,
            matchingSpotCount: spots.count,
            isLimited: isLimited
        )
    }

    /// The budget rule: keep the best `limit` spots and report the score that
    /// let them in, so the UI can say "showing the strongest 300 above 0.42"
    /// instead of quietly thinning the map.
    static func capped(
        _ ranked: [Spot],
        requestedMinimumScore: Double,
        limit: Int
    ) -> (spots: [Spot], floor: Double, isLimited: Bool) {
        guard ranked.count > limit, limit > 0 else {
            return (ranked, requestedMinimumScore, false)
        }
        let floor = ranked[limit - 1].score
        return (Array(ranked.prefix(limit)), max(requestedMinimumScore, floor), true)
    }

    /// Curated last, so it draws on top; within that, low scores first so the
    /// big markers sit over the small ones.
    static func drawingOrder(_ clusters: [SpotCluster]) -> [SpotCluster] {
        clusters.sorted { lhs, rhs in
            let lhsCurated = lhs.representative.curated
            let rhsCurated = rhs.representative.curated
            if lhsCurated != rhsCurated { return !lhsCurated }
            let lhsScore = lhs.representative.score
            let rhsScore = rhs.representative.score
            return lhsScore == rhsScore ? lhs.id > rhs.id : lhsScore < rhsScore
        }
    }

    /// Equal-angle grid over the visible box. Cells are a fixed fraction of the
    /// region, so a bubble breaks apart at the same zoom wherever you are.
    static func cluster(_ spots: [Spot], in region: BoundingBox) -> [SpotCluster] {
        guard !spots.isEmpty else { return [] }
        let lonCell = max((region.maxLon - region.minLon) / clusterColumns, 1e-9)
        // Latitude cells are shortened by the same factor the projection
        // stretches them, so cells stay roughly square on screen.
        let latCell = max(lonCell * cos(region.center.latitude * .pi / 180), 1e-9)

        var cells: [Cell: [Spot]] = [:]
        for spot in spots {
            let cell = Cell(
                x: Int(floor(spot.lon / lonCell)),
                y: Int(floor(spot.lat / latCell))
            )
            cells[cell, default: []].append(spot)
        }

        return cells.values.map { members in
            let latitude = members.reduce(0) { $0 + $1.lat } / Double(members.count)
            let longitude = members.reduce(0) { $0 + $1.lon } / Double(members.count)
            return SpotCluster(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                spots: members
            )
        }
    }

    struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    /// The width of the visible rectangle in metres, measured across its middle.
    public static func visibleSpanMetres(of region: BoundingBox) -> Double {
        let latitude = region.center.latitude
        let west = Coordinate(latitude: latitude, longitude: region.minLon)
        let east = Coordinate(latitude: latitude, longitude: region.maxLon)
        return west.distance(to: east)
    }
}
