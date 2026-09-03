import Foundation
import TDMCore

/// The enum half of the name `SpotSource`. Inside spotforge, `SpotSource` is
/// the protocol a fetcher conforms to — `docs/SPOTFORGE.md` — so the model's
/// enum travels under a name that cannot be confused with it.
public typealias SourceKind = SpotSourceKind

/// One candidate as a source returned it, before merge and before scoring.
///
/// It is deliberately not a `Spot`: `score` is meaningless until the city-wide
/// pass runs, and the raw signals the scorer needs — the Commons photo count,
/// the Wikidata sitelink count, a curated boost — have nowhere to live on the
/// published type.
public struct RawSpot: Sendable, Hashable {
    public var source: SourceKind
    /// The part after the colon in the published id, e.g. `node/357555716`.
    public var sourceId: String
    public var name: String
    public var coordinate: Coordinate
    public var kind: SpotKind
    public var tags: [String]
    public var openness: Openness
    /// Degrees from north, 0–180.
    public var streetBearing: Double?
    public var bestHours: [Int]?
    public var note: String?
    public var refs: [String: String]
    public var photos: [SpotPhoto]
    /// Wikipedia language editions, when the source knows.
    public var sitelinks: Int?
    /// `score_boost` from the curated YAML, added before normalisation.
    public var curationBoost: Double
    public var curationNote: String?

    public init(
        source: SourceKind,
        sourceId: String,
        name: String = "",
        coordinate: Coordinate,
        kind: SpotKind = .other,
        tags: [String] = [],
        openness: Openness = .open,
        streetBearing: Double? = nil,
        bestHours: [Int]? = nil,
        note: String? = nil,
        refs: [String: String] = [:],
        photos: [SpotPhoto] = [],
        sitelinks: Int? = nil,
        curationBoost: Double = 0,
        curationNote: String? = nil
    ) {
        self.source = source
        self.sourceId = sourceId
        self.name = name
        self.coordinate = coordinate
        self.kind = kind
        self.tags = tags
        self.openness = openness
        self.streetBearing = streetBearing
        self.bestHours = bestHours
        self.note = note
        self.refs = refs
        self.photos = photos
        self.sitelinks = sitelinks
        self.curationBoost = curationBoost
        self.curationNote = curationNote
    }

    public var id: String { "\(source.rawValue):\(sourceId)" }

    /// The normalise stage: a candidate as the merger and the schema see it.
    ///
    /// `score` is zero here and stays zero until `SpotScorer` runs over the
    /// whole city — there is no meaningful per-spot score before then.
    public var normalised: Spot {
        Spot(
            id: id,
            name: name,
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            kind: kind,
            sources: [source],
            score: 0,
            scoreFactors: [],
            tags: tags.map { $0.lowercased() }.sorted(),
            bestHours: bestHours?.filter { (0...23).contains($0) }.sorted(),
            streetBearing: streetBearing.map { Geometry.normalisedBearing($0) },
            openness: openness,
            note: note,
            refs: refs,
            // Attribution is not optional: a photo without an author or a
            // licence is dropped here rather than shipped unattributable.
            photos: photos.filter(\.isAttributed),
            curated: source == .curated
        )
    }
}

/// A source of candidates. `docs/SPOTFORGE.md` §1.
///
/// One method, one box in, candidates out — which is what makes the pipeline
/// testable against recorded fixtures instead of volunteer-run infrastructure.
public protocol SpotSource: Sendable {
    /// Which source this is, for the report and for the merge priority.
    var sourceKind: SourceKind { get }
    func fetch(bbox: BoundingBox) async throws -> [RawSpot]
}

public enum Geometry {
    /// Bearings live on 0–180 in the schema: a street has an axis, not a
    /// direction, and "north-east" and "south-west" are the same street.
    public static func normalisedBearing(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var value = degrees.truncatingRemainder(dividingBy: 180)
        if value < 0 { value += 180 }
        return value
    }

    /// Initial great-circle bearing in degrees from north, 0–360.
    ///
    /// Radians only inside; the `Rad` suffix marks them, because a stray
    /// degrees/radians conversion here is invisible in the output.
    public static func bearing(from start: Coordinate, to end: Coordinate) -> Double {
        let startLatRad = start.latitude * .pi / 180
        let endLatRad = end.latitude * .pi / 180
        let deltaLonRad = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLonRad) * cos(endLatRad)
        let x = cos(startLatRad) * sin(endLatRad) - sin(startLatRad) * cos(endLatRad) * cos(deltaLonRad)
        let bearingRad = atan2(y, x)
        let degrees = bearingRad * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
