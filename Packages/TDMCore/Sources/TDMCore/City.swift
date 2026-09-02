import Foundation

/// Who the data belongs to. Displayed, not merely stored — see
/// `docs/DATA-BUNDLES.md` ("Attribution").
public struct Attribution: Sendable, Hashable, Codable {
    public var osm: String?
    public var wikidata: String?
    public var commons: String?

    public init(osm: String? = nil, wikidata: String? = nil, commons: String? = nil) {
        self.osm = osm
        self.wikidata = wikidata
        self.commons = commons
    }

    /// The lines the UI has to show, in a stable order.
    public var displayLines: [String] {
        [osm, wikidata, commons].compactMap { $0 }
    }
}

/// One row of `index.json`: enough to decide whether to download a city, and to
/// verify the download once it arrives.
public struct CityIndexEntry: Sendable, Hashable, Codable, Identifiable {
    /// `{ISO-3166-1-alpha-2}-{slug}`, lowercase: `us-nyc`.
    public var cityId: String
    public var name: String
    public var country: String
    public var lat: Double
    public var lon: Double
    public var bbox: BoundingBox
    public var spotCount: Int
    /// Compressed size. Shown before download — on roaming data that matters.
    public var bytes: Int
    /// Over the **decompressed** JSON, lowercase hex.
    public var sha256: String
    /// Increments on every regeneration; the client re-downloads when its
    /// stored version is lower.
    public var bundleVersion: Int
    public var updatedAt: Date

    public var id: String { cityId }

    public init(
        cityId: String,
        name: String,
        country: String,
        lat: Double,
        lon: Double,
        bbox: BoundingBox,
        spotCount: Int,
        bytes: Int,
        sha256: String,
        bundleVersion: Int,
        updatedAt: Date
    ) {
        self.cityId = cityId
        self.name = name
        self.country = country
        self.lat = lat
        self.lon = lon
        self.bbox = bbox
        self.spotCount = spotCount
        self.bytes = bytes
        self.sha256 = sha256
        self.bundleVersion = bundleVersion
        self.updatedAt = updatedAt
    }

    public var center: Coordinate { Coordinate(latitude: lat, longitude: lon) }

    /// The path under the bundle root, relative to the versioned directory.
    public var bundlePath: String { "cities/\(cityId).json.gz" }

    public var isValid: Bool {
        !cityId.isEmpty && center.isValid && bbox.isValid && spotCount >= 0 && bytes >= 0
            && sha256.count == 64
            && sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// `index.json`: small, fetched first, cached for an hour.
public struct CityIndex: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var cities: [CityIndexEntry]

    public init(schemaVersion: Int = TDMCore.bundleSchemaVersion, generatedAt: Date, cities: [CityIndexEntry]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.cities = cities
    }

    public func entry(for cityId: String) -> CityIndexEntry? {
        cities.first { $0.cityId == cityId }
    }

    /// The city a coordinate is in: the box that contains it, and where several
    /// do — Manhattan sits inside more than one plausible box — the one whose
    /// centre is nearest. `docs/SPEC-map.md`, "City detection".
    public func city(containing coordinate: Coordinate) -> CityIndexEntry? {
        cities
            .filter { $0.bbox.contains(coordinate) }
            .min { $0.center.distance(to: coordinate) < $1.center.distance(to: coordinate) }
    }

    /// Every city, nearest first — what the city picker lists.
    public func citiesSortedByDistance(from coordinate: Coordinate) -> [CityIndexEntry] {
        cities.sorted { $0.center.distance(to: coordinate) < $1.center.distance(to: coordinate) }
    }
}

/// One city's bundle: the decompressed contents of `cities/{id}.json.gz`.
public struct City: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var cityId: String
    public var name: String
    public var country: String
    public var bundleVersion: Int
    public var generatedAt: Date
    /// The tool and version that wrote this, e.g. `spotforge 0.1.0`. In a diff
    /// of a regenerated bundle this is the first thing you want to see.
    public var generator: String
    public var bbox: BoundingBox
    public var attribution: Attribution
    /// The score floor the size cap forced, when it forced one. Recorded so it
    /// is visible *why* a known spot is missing rather than silently absent.
    public var scoreFloor: Double?
    public var spots: [Spot]

    public var id: String { cityId }

    public init(
        schemaVersion: Int = TDMCore.bundleSchemaVersion,
        cityId: String,
        name: String,
        country: String,
        bundleVersion: Int,
        generatedAt: Date,
        generator: String,
        bbox: BoundingBox,
        attribution: Attribution,
        scoreFloor: Double? = nil,
        spots: [Spot]
    ) {
        self.schemaVersion = schemaVersion
        self.cityId = cityId
        self.name = name
        self.country = country
        self.bundleVersion = bundleVersion
        self.generatedAt = generatedAt
        self.generator = generator
        self.bbox = bbox
        self.attribution = attribution
        self.scoreFloor = scoreFloor
        self.spots = spots
    }

    public var spotCount: Int { spots.count }

    public var curatedSpots: [Spot] { spots.filter(\.curated) }

    public var isValid: Bool {
        !cityId.isEmpty && bbox.isValid && bundleVersion >= 1 && spots.allSatisfy(\.isValid)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, cityId, name, country, bundleVersion, generatedAt, generator
        case bbox, attribution, scoreFloor, spots
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        cityId = try container.decode(String.self, forKey: .cityId)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        bundleVersion = try container.decode(Int.self, forKey: .bundleVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        generator = try container.decode(String.self, forKey: .generator)
        bbox = try container.decode(BoundingBox.self, forKey: .bbox)
        attribution = try container.decodeIfPresent(Attribution.self, forKey: .attribution) ?? Attribution()
        scoreFloor = try container.decodeIfPresent(Double.self, forKey: .scoreFloor)
        spots = try container.decodeIfPresent([Spot].self, forKey: .spots) ?? []
    }
}
