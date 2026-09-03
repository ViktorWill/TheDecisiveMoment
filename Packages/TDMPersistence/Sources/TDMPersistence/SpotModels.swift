#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore
import TDMSpots

/// A city bundle as stored: the header of `cities/{id}.json.gz`, with its spots
/// hanging off it as rows.
///
/// The rows are the point. `docs/ARCHITECTURE.md` decides for SwiftData partly
/// because a decoded bundle can be indexed; a blob per city would mean loading
/// New York to draw one street.
@Model
public final class StoredCityBundle {
    @Attribute(.unique) public var cityId: String = ""
    public var name: String = ""
    public var country: String = ""
    public var bundleVersion: Int = 0
    public var generatedAt: Date = Date.distantPast
    public var generator: String = ""
    public var minLat: Double = 0
    public var minLon: Double = 0
    public var maxLat: Double = 0
    public var maxLon: Double = 0
    /// The floor the pipeline's size cap forced, when it forced one — kept so
    /// the UI can explain why a spot someone knows is not in the bundle.
    public var scoreFloor: Double?
    public var attributionOSM: String?
    public var attributionWikidata: String?
    public var attributionCommons: String?
    public var spotCount: Int = 0
    /// When this device imported it, which is what "stored" means to the user.
    public var importedAt: Date = Date.distantPast

    public init(_ city: City, importedAt: Date = Date()) {
        cityId = city.cityId
        apply(city, importedAt: importedAt)
    }

    public func apply(_ city: City, importedAt: Date = Date()) {
        name = city.name
        country = city.country
        bundleVersion = city.bundleVersion
        generatedAt = city.generatedAt
        generator = city.generator
        minLat = city.bbox.minLat
        minLon = city.bbox.minLon
        maxLat = city.bbox.maxLat
        maxLon = city.bbox.maxLon
        scoreFloor = city.scoreFloor
        attributionOSM = city.attribution.osm
        attributionWikidata = city.attribution.wikidata
        attributionCommons = city.attribution.commons
        spotCount = city.spots.count
        self.importedAt = importedAt
    }

    public var boundingBox: BoundingBox {
        BoundingBox(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
    }

    public var summary: StoredCitySummary {
        StoredCitySummary(
            cityId: cityId,
            name: name,
            country: country,
            spotCount: spotCount,
            bundleVersion: bundleVersion,
            generatedAt: generatedAt,
            importedAt: importedAt,
            bbox: boundingBox,
            attribution: Attribution(
                osm: attributionOSM,
                wikidata: attributionWikidata,
                commons: attributionCommons
            ),
            scoreFloor: scoreFloor
        )
    }
}

/// One spot of a stored bundle.
///
/// Flat columns for everything the map queries — latitude, longitude, score,
/// kind — and JSON for the two arrays it only reads once a sheet is open. The
/// bounding-box query has to be an index scan, not a decode of the city.
@Model
public final class StoredSpot {
    @Attribute(.unique) public var id: String = ""
    public var cityId: String = ""
    public var name: String = ""
    public var lat: Double = 0
    public var lon: Double = 0
    public var kindRawValue: String = SpotKind.other.rawValue
    public var opennessRawValue: String = Openness.open.rawValue
    public var sourceRawValues: [String] = []
    public var score: Double = 0
    public var tags: [String] = []
    public var bestHours: [Int]?
    public var streetBearing: Double?
    public var note: String?
    public var curated: Bool = false
    public var refs: [String: String] = [:]
    /// `[ScoreFactor]`, canonical JSON.
    public var scoreFactorsData: Data = Data()
    /// `[SpotPhoto]`, canonical JSON. Attribution travels with the photo, so it
    /// cannot be stored apart from it and forgotten.
    public var photosData: Data = Data()

    public init(_ spot: Spot, cityId: String) {
        id = spot.id
        self.cityId = cityId
        apply(spot)
    }

    public func apply(_ spot: Spot) {
        name = spot.name
        lat = spot.lat
        lon = spot.lon
        kindRawValue = spot.kind.rawValue
        opennessRawValue = spot.openness.rawValue
        sourceRawValues = spot.sources.map(\.rawValue)
        score = spot.score
        tags = spot.tags
        bestHours = spot.bestHours
        streetBearing = spot.streetBearing
        note = spot.note
        curated = spot.curated
        refs = spot.refs
        scoreFactorsData = SpotCoding.encode(spot.scoreFactors)
        photosData = SpotCoding.encode(spot.photos)
    }

    public var value: Spot {
        Spot(
            id: id,
            name: name,
            lat: lat,
            lon: lon,
            kind: SpotKind(rawValue: kindRawValue) ?? .other,
            sources: sourceRawValues.compactMap(SpotSource.init(rawValue:)),
            score: score,
            scoreFactors: SpotCoding.decode([ScoreFactor].self, from: scoreFactorsData) ?? [],
            tags: tags,
            bestHours: bestHours,
            streetBearing: streetBearing,
            openness: Openness(rawValue: opennessRawValue) ?? .open,
            note: note,
            refs: refs,
            photos: SpotCoding.decode([SpotPhoto].self, from: photosData) ?? [],
            curated: curated
        )
    }
}

/// A pin the user dropped.
///
/// A separate model from ``StoredSpot`` on purpose: a bundle refresh deletes
/// every row of the city it replaces, and the one guarantee `docs/SPEC-map.md`
/// makes about pins is that this never touches them. Two tables make that a
/// property of the schema rather than of a careful predicate.
@Model
public final class StoredPin {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var lat: Double = 0
    public var lon: Double = 0
    public var kindRawValue: String = SpotKind.street.rawValue
    public var opennessRawValue: String = Openness.open.rawValue
    public var tags: [String] = []
    public var note: String?
    public var streetBearing: Double?
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date = Date.distantPast

    public init(_ spot: Spot, createdAt: Date = Date()) {
        id = spot.id
        self.createdAt = createdAt
        apply(spot, updatedAt: createdAt)
    }

    public func apply(_ spot: Spot, updatedAt: Date = Date()) {
        name = spot.name
        lat = spot.lat
        lon = spot.lon
        kindRawValue = spot.kind.rawValue
        opennessRawValue = spot.openness.rawValue
        tags = spot.tags
        note = spot.note
        streetBearing = spot.streetBearing
        self.updatedAt = updatedAt
    }

    public var value: Spot {
        LocalPin.make(
            id: id,
            name: name,
            coordinate: Coordinate(latitude: lat, longitude: lon),
            kind: SpotKind(rawValue: kindRawValue) ?? .street,
            openness: Openness(rawValue: opennessRawValue) ?? .open,
            tags: tags,
            note: note,
            streetBearingDegrees: streetBearing
        )
    }
}

/// `index.json` as last fetched, with the instant it arrived.
///
/// One row: the index is small, it is always fetched whole, and the timestamp is
/// what the one-hour cache of `docs/DATA-BUNDLES.md` is measured from.
@Model
public final class StoredCityIndex {
    @Attribute(.unique) public var identifier: String = StoredCityIndex.singletonIdentifier
    public var data: Data = Data()
    public var fetchedAt: Date = Date.distantPast

    public static let singletonIdentifier = "index.json"

    public init(data: Data, fetchedAt: Date) {
        identifier = Self.singletonIdentifier
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// The JSON used inside a row, which is the bundle's own canonical JSON so a
/// stored spot re-encodes to the bytes it was decoded from.
enum SpotCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? BundleCoding.encoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? BundleCoding.decoder().decode(type, from: data)
    }
}
#endif
