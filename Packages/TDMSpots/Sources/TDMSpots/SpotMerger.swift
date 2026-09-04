import Foundation
import TDMCore

/// Thresholds for the dedupe rule, `docs/SPOTFORGE.md` §7.
public struct MergeRules: Sendable, Hashable {
    /// Great-circle distance below which two candidates may be the same place.
    public var maxDistanceMetres: Double
    /// Intersections are genuinely dense — two corners of the same junction are
    /// different places to stand — so they get a tighter radius.
    public var intersectionDistanceMetres: Double
    /// Jaro-Winkler over normalised names.
    public var minimumNameSimilarity: Double

    public init(
        maxDistanceMetres: Double = 60,
        intersectionDistanceMetres: Double = 25,
        minimumNameSimilarity: Double = 0.82
    ) {
        self.maxDistanceMetres = maxDistanceMetres
        self.intersectionDistanceMetres = intersectionDistanceMetres
        self.minimumNameSimilarity = minimumNameSimilarity
    }

    public static let standard = MergeRules()
}

/// Dedupe across sources.
///
/// Merging pairwise as candidates arrive is order-dependent: A merges with B,
/// and the merged position may then be out of range of C, which A alone would
/// have caught. So the pass is single-link clustering over the whole candidate
/// set — the "same place" relation is symmetric, and its transitive closure is
/// therefore independent of the order the sources were fetched in — followed by
/// one reduction per cluster.
public enum SpotMerger {
    /// Which source wins when two disagree. `docs/SPOTFORGE.md` §7.
    static func priority(of source: SpotSource) -> Int {
        switch source {
        case .local: 5      // the user's own pin beats anything generated
        case .curated: 4
        case .wikidata: 3
        case .osm: 2
        case .commons: 1
        }
    }

    /// How far the merged coordinate is pulled toward each contributor.
    ///
    /// Curated positions are where a person actually stood; OSM's `out center`
    /// is a reasonable centroid; a Wikidata point is often the middle of a
    /// building and a Commons point is wherever the camera was, which may be a
    /// street away.
    static func positionWeight(of source: SpotSource) -> Double {
        switch source {
        case .local, .curated: 3
        case .osm: 2
        case .wikidata, .commons: 1
        }
    }

    /// The candidate set reduced to one spot per place.
    ///
    /// Output is sorted by id, so the result is a value determined by the input
    /// set alone and not by its order.
    public static func merge(_ candidates: [Spot], rules: MergeRules = .standard) -> [Spot] {
        guard candidates.count > 1 else { return candidates }

        // Ids are meant to be unique, but a source that returns the same
        // record twice must not change the outcome either, so the ordering
        // falls back to the contents that the reduction actually reads.
        let ordered = candidates.sorted { isOrderedBefore($0, $1) }
        var clusters = DisjointSet(count: ordered.count)

        // A naive all-pairs sweep is O(n²), which is fine for a fixture set
        // and ruinous for a real city — hundreds of thousands of OSM features
        // pegs a core for hours (PR #16). `ProximityGrid` buckets every
        // candidate at the *larger* of the two radii the rule uses, so the
        // tighter `intersectionDistanceMetres` case is still caught, and each
        // candidate is only compared against the 3×3 neighbourhood of cells
        // around it rather than every other candidate.
        let grid = ProximityGrid(coordinates: ordered.map(\.coordinate), cellMetres: rules.maxDistanceMetres)
        for i in ordered.indices {
            for j in grid.neighbours(of: i) where j > i && isSamePlace(ordered[i], ordered[j], rules: rules) {
                clusters.union(i, j)
            }
        }

        var grouped: [Int: [Spot]] = [:]
        for (index, spot) in ordered.enumerated() {
            grouped[clusters.find(index), default: []].append(spot)
        }

        return grouped.values.map(reduce).sorted { isOrderedBefore($0, $1) }
    }

    /// Both halves of the §7 rule: close enough, and either agreeing on the name
    /// or one of them not offering one.
    public static func isSamePlace(_ lhs: Spot, _ rhs: Spot, rules: MergeRules = .standard) -> Bool {
        let limit = (lhs.kind == .intersection || rhs.kind == .intersection)
            ? rules.intersectionDistanceMetres
            : rules.maxDistanceMetres
        guard lhs.coordinate.distance(to: rhs.coordinate) < limit else { return false }

        let lhsName = SpotName.normalized(lhs.name)
        let rhsName = SpotName.normalized(rhs.name)
        if lhsName.isEmpty || rhsName.isEmpty { return true }
        return SpotName.similarity(lhs.name, rhs.name) > rules.minimumNameSimilarity
    }

    /// One cluster into one spot. Every choice below is a total order over the
    /// members, so the reduction does not depend on their order either.
    static func reduce(_ cluster: [Spot]) -> Spot {
        let members = cluster.sorted { lhs, rhs in
            let lhsPriority = priority(of: lhs)
            let rhsPriority = priority(of: rhs)
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            return isOrderedBefore(lhs, rhs)
        }
        guard var merged = members.first else {
            preconditionFailure("a cluster is never empty")
        }

        merged.sources = SpotSource.allCases.filter { source in
            members.contains { $0.sources.contains(source) }
        }
        merged.tags = Set(members.flatMap(\.tags)).sorted()
        merged.curated = members.contains(where: \.curated)

        // A curated name and note are the reason curation exists; below that,
        // the highest-priority member that has one at all.
        merged.name = members.first { $0.curated && !$0.name.isEmpty }?.name
            ?? members.first { !$0.name.isEmpty }?.name
            ?? merged.name
        merged.note = members.first { $0.curated && $0.note != nil }?.note
            ?? members.compactMap(\.note).first
        merged.kind = members.first { $0.curated && $0.kind != .other }?.kind
            ?? members.first { $0.kind != .other }?.kind
            ?? .other

        // Conservative on openness: a wrong `canyon` costs the user 3.5 stops,
        // so unless a human said otherwise, take the most open reading.
        merged.openness = members.first { $0.curated }?.openness
            ?? [Openness.open, .canyon, .covered].first { value in
                members.contains { $0.openness == value }
            }
            ?? .open

        // Bearings are circular and do not average, so take the best single
        // reading rather than a mean that could point across the street.
        merged.streetBearing = members.first { $0.curated && $0.streetBearing != nil }?.streetBearing
            ?? members.compactMap(\.streetBearing).first

        let hours = Set(members.compactMap(\.bestHours).flatMap { $0 })
        merged.bestHours = hours.isEmpty ? nil : hours.sorted()

        var totalWeight = 0.0
        var latitude = 0.0
        var longitude = 0.0
        for member in members {
            let weight = member.sources.map(positionWeight).max() ?? 1
            totalWeight += weight
            latitude += member.lat * weight
            longitude += member.lon * weight
        }
        if totalWeight > 0 {
            merged.lat = latitude / totalWeight
            merged.lon = longitude / totalWeight
        }

        // Highest-priority member wins a key it defines; the rest fill gaps.
        var refs: [String: String] = [:]
        for member in members.reversed() {
            refs.merge(member.refs) { _, newer in newer }
        }
        merged.refs = refs

        var photos: [SpotPhoto] = []
        for member in members {
            for photo in member.photos where !photos.contains(where: { $0.pageURL == photo.pageURL }) {
                photos.append(photo)
            }
        }
        merged.photos = photos

        // Keep the maximum of each factor, and the score the scorer would have
        // to beat. Both are recomputed by `SpotScorer` when the city is ranked.
        var bestFactors: [ScoreFactorKind: ScoreFactor] = [:]
        for factor in members.flatMap(\.scoreFactors) {
            if let existing = bestFactors[factor.kind], existing.contribution >= factor.contribution { continue }
            bestFactors[factor.kind] = factor
        }
        merged.scoreFactors = ScoreFactorKind.allCases.compactMap { bestFactors[$0] }
        merged.score = members.map(\.score).max() ?? merged.score

        return merged
    }

    /// A total order over candidates: id first, then the fields the reduction
    /// reads, so two records sharing an id still sort deterministically.
    static func isOrderedBefore(_ lhs: Spot, _ rhs: Spot) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.lat != rhs.lat { return lhs.lat < rhs.lat }
        if lhs.lon != rhs.lon { return lhs.lon < rhs.lon }
        if lhs.curated != rhs.curated { return lhs.curated }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return String(describing: lhs.refs) < String(describing: rhs.refs)
    }

    private static func priority(of spot: Spot) -> Int {
        let fromSources = spot.sources.map(priority).max() ?? 0
        let fromId = spot.idSource.flatMap(SpotSource.init(rawValue:)).map(priority) ?? 0
        return max(fromSources, fromId)
    }
}

/// Buckets coordinates into a grid so nearby candidates can be found without
/// comparing every candidate against every other one.
///
/// The cell size is fixed metres, so longitude cells are narrowed by
/// `cos(latitude)` at one reference latitude for the whole set — citywide, not
/// per candidate, which keeps two runs over the same input agreeing even
/// though summing floating-point latitudes could differ in the last bit by
/// input order. `coordinates` is always iterated in the caller's fixed,
/// content-sorted order, so the reference latitude is reproducible.
struct ProximityGrid {
    private struct Cell: Hashable {
        var latIndex: Int
        var lonIndex: Int
    }

    /// Metres per degree of latitude, spherical Earth — same constant
    /// `PhotoDensityGrid` in the spotforge tool uses for the same bucketing.
    private static let metresPerDegreeLatitude = 111_320.0

    private let cellDegreesLatitude: Double
    private let cellDegreesLongitude: Double
    private let cells: [Cell: [Int]]
    private let cellOf: [Cell]

    init(coordinates: [Coordinate], cellMetres: Double) {
        let referenceLatitudeRad: Double
        if coordinates.isEmpty {
            referenceLatitudeRad = 0
        } else {
            let sum = coordinates.reduce(0.0) { $0 + $1.latitude }
            referenceLatitudeRad = (sum / Double(coordinates.count)) * .pi / 180
        }
        let cellMetres = max(cellMetres, 1)
        cellDegreesLatitude = cellMetres / Self.metresPerDegreeLatitude
        let scale = max(0.01, cos(referenceLatitudeRad))
        cellDegreesLongitude = cellMetres / (Self.metresPerDegreeLatitude * scale)

        var cells: [Cell: [Int]] = [:]
        var cellOf: [Cell] = []
        cellOf.reserveCapacity(coordinates.count)
        for (index, coordinate) in coordinates.enumerated() {
            let cell = Cell(
                latIndex: Int((coordinate.latitude / cellDegreesLatitude).rounded(.down)),
                lonIndex: Int((coordinate.longitude / cellDegreesLongitude).rounded(.down))
            )
            cells[cell, default: []].append(index)
            cellOf.append(cell)
        }
        self.cells = cells
        self.cellOf = cellOf
    }

    /// Every candidate sharing `index`'s cell or one of its eight neighbours —
    /// a 3×3 block whose side is three times the cell size, so two candidates
    /// up to `cellMetres` apart are always in each other's block regardless of
    /// where within their cells they fall.
    func neighbours(of index: Int) -> [Int] {
        let origin = cellOf[index]
        var result: [Int] = []
        for latOffset in -1...1 {
            for lonOffset in -1...1 {
                let cell = Cell(latIndex: origin.latIndex + latOffset, lonIndex: origin.lonIndex + lonOffset)
                if let indices = cells[cell] { result.append(contentsOf: indices) }
            }
        }
        return result
    }
}

/// Union-find, which is all single-link clustering needs.
struct DisjointSet {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return }
        if rank[lhsRoot] < rank[rhsRoot] {
            parent[lhsRoot] = rhsRoot
        } else if rank[lhsRoot] > rank[rhsRoot] {
            parent[rhsRoot] = lhsRoot
        } else {
            parent[rhsRoot] = lhsRoot
            rank[lhsRoot] += 1
        }
    }
}
