import Foundation

/// What a place is, in terms of what it means to a street photographer —
/// geometry, light and human flow — rather than OSM's taxonomy.
///
/// The OSM tag mapping is in `docs/SPOTFORGE.md` §2.
public enum SpotKind: String, Sendable, Codable, CaseIterable, Hashable {
    case plaza
    case market
    case street
    case bridge
    case stairs
    case underpass
    case arcade
    case transit
    case waterfront
    case park
    case viewpoint
    case intersection
    case landmark
    case other
}

/// Where a spot came from. `sources` is the union after dedupe.
public enum SpotSource: String, Sendable, Codable, CaseIterable, Hashable {
    case osm
    case wikidata
    case commons
    case curated
    /// A pin the user dropped. Never present in a bundle — these live only in
    /// `TDMPersistence` and are merged into the map at read time.
    case local
}

/// A second name for ``SpotSource``.
///
/// In `spotforge`, `SpotSource` is the protocol a fetcher conforms to
/// (`docs/SPOTFORGE.md` §1), and `TDMCore.SpotSource` cannot disambiguate this
/// enum there because the module's name is shadowed by the ``TDMCore``
/// namespace. This is the name that build uses for the enum.
public typealias SpotSourceKind = SpotSource

/// How much sky the place can see.
///
/// Maps directly onto the scene modifier in `docs/EXPOSURE-MODEL.md` §4c, which
/// is why it is worth carrying in the bundle: selecting a spot pre-fills the
/// Light screen without the user describing the street.
public enum Openness: String, Sendable, Codable, CaseIterable, Hashable {
    case open
    case canyon
    case covered
}

/// Which term of `docs/SPOTFORGE.md` §8 a contribution came from.
public enum ScoreFactorKind: String, Sendable, Codable, CaseIterable, Hashable {
    case photoDensity
    case notability
    case featurePrior
    case curation
}

/// One term of a spot's score, with the sentence the UI shows for it.
///
/// The UI renders `detail`, never `contribution` alone: "137 geotagged photos
/// nearby · marketplace · curated" tells the user something, "0.87" does not.
public struct ScoreFactor: Sendable, Hashable, Codable {
    public var kind: ScoreFactorKind
    public var contribution: Double
    public var detail: String

    public init(kind: ScoreFactorKind, contribution: Double, detail: String) {
        self.kind = kind
        self.contribution = contribution
        self.detail = detail
    }
}

/// A hot-linked Commons thumbnail.
///
/// Photos are never rehosted, and author and licence are mandatory: an entry
/// that cannot be attributed does not go in the bundle.
public struct SpotPhoto: Sendable, Hashable, Codable {
    public var thumbURL: String
    public var pageURL: String
    public var author: String
    public var license: String

    public init(thumbURL: String, pageURL: String, author: String, license: String) {
        self.thumbURL = thumbURL
        self.pageURL = pageURL
        self.author = author
        self.license = license
    }

    /// Attribution is only satisfied when both halves are there to display.
    public var isAttributed: Bool {
        !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A place worth walking to.
///
/// The wire format is `docs/DATA-BUNDLES.md`; the field names here are the JSON
/// field names, because `spotforge` writes this same type.
public struct Spot: Sendable, Hashable, Codable, Identifiable {
    /// `{source}:{sourceId}`, stable across regenerations — user pins,
    /// favourites and visit history join against it.
    public var id: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var kind: SpotKind
    public var sources: [SpotSource]
    /// `0…1`, normalised within the city.
    public var score: Double
    public var scoreFactors: [ScoreFactor]
    /// Free-form, lowercase.
    public var tags: [String]
    /// Local hours 0–23. `nil` when unknown, rather than an empty list that
    /// would read as "never any good".
    public var bestHours: [Int]?
    /// Degrees from north of the dominant street axis, 0–180.
    public var streetBearing: Double?
    public var openness: Openness
    public var note: String?
    /// Source identifiers, for deep links and for re-merging on the next build.
    public var refs: [String: String]
    public var photos: [SpotPhoto]
    public var curated: Bool

    public init(
        id: String,
        name: String,
        lat: Double,
        lon: Double,
        kind: SpotKind,
        sources: [SpotSource],
        score: Double,
        scoreFactors: [ScoreFactor] = [],
        tags: [String] = [],
        bestHours: [Int]? = nil,
        streetBearing: Double? = nil,
        openness: Openness = .open,
        note: String? = nil,
        refs: [String: String] = [:],
        photos: [SpotPhoto] = [],
        curated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.kind = kind
        self.sources = sources
        self.score = score
        self.scoreFactors = scoreFactors
        self.tags = tags
        self.bestHours = bestHours
        self.streetBearing = streetBearing
        self.openness = openness
        self.note = note
        self.refs = refs
        self.photos = photos
        self.curated = curated
    }

    public var coordinate: Coordinate {
        get { Coordinate(latitude: lat, longitude: lon) }
        set {
            lat = newValue.latitude
            lon = newValue.longitude
        }
    }

    /// The source half of the id, which is what gives ids their stability.
    public var idSource: String? {
        guard let separator = id.firstIndex(of: ":"), separator > id.startIndex else { return nil }
        return String(id[id.startIndex..<separator])
    }

    /// Everything that has to hold before a spot may be shown or stored.
    ///
    /// Deliberately not thrown from `init(from:)`: a decoder that rejects a
    /// whole city because one spot has a bearing of 361° is worse than one that
    /// lets the caller decide.
    public var isValid: Bool {
        !id.isEmpty
            && coordinate.isValid
            && score >= 0 && score <= 1
            && (bestHours?.allSatisfy { (0...23).contains($0) } ?? true)
            && (streetBearing.map { $0 >= 0 && $0 <= 180 } ?? true)
            && photos.allSatisfy(\.isAttributed)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, lat, lon, kind, sources, score, scoreFactors, tags
        case bestHours, streetBearing, openness, note, refs, photos, curated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        kind = try container.decode(SpotKind.self, forKey: .kind)
        sources = try container.decodeIfPresent([SpotSource].self, forKey: .sources) ?? []
        score = try container.decode(Double.self, forKey: .score)
        scoreFactors = try container.decodeIfPresent([ScoreFactor].self, forKey: .scoreFactors) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        bestHours = try container.decodeIfPresent([Int].self, forKey: .bestHours)
        streetBearing = try container.decodeIfPresent(Double.self, forKey: .streetBearing)
        openness = try container.decodeIfPresent(Openness.self, forKey: .openness) ?? .open
        note = try container.decodeIfPresent(String.self, forKey: .note)
        refs = try container.decodeIfPresent([String: String].self, forKey: .refs) ?? [:]
        photos = try container.decodeIfPresent([SpotPhoto].self, forKey: .photos) ?? []
        curated = try container.decodeIfPresent(Bool.self, forKey: .curated) ?? false
    }
}
