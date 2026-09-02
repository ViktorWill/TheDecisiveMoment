import Foundation

/// A WGS 84 position, in degrees.
///
/// Angles are degrees at every API boundary; the radian conversion lives inside
/// ``distance(to:)`` and is named accordingly.
public struct Coordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Whether the pair is a position on Earth at all.
    ///
    /// A bundle that carries a swapped lat/lon — the most common data error in
    /// this pipeline — usually fails this, because most longitudes are outside
    /// ±90°.
    public var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
            && latitude.isFinite && longitude.isFinite
    }

    /// Great-circle distance in metres, spherical Earth.
    ///
    /// The haversine formula on a mean Earth radius of 6 371 008.8 m (IUGG).
    /// Good to ~0.5 % — the merge threshold in `docs/SPOTFORGE.md` §7 is 60 m,
    /// so ellipsoidal accuracy would buy nothing.
    public func distance(to other: Coordinate) -> Double {
        let earthRadiusMetres = 6_371_008.8
        let latitudeRad = latitude * .pi / 180
        let otherLatitudeRad = other.latitude * .pi / 180
        let deltaLatitudeRad = (other.latitude - latitude) * .pi / 180
        let deltaLongitudeRad = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLatitudeRad / 2) * sin(deltaLatitudeRad / 2)
            + cos(latitudeRad) * cos(otherLatitudeRad)
            * sin(deltaLongitudeRad / 2) * sin(deltaLongitudeRad / 2)
        return 2 * earthRadiusMetres * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

/// An axis-aligned box in degrees, as written in `index.json`.
///
/// Antimeridian-crossing boxes are out of scope: no city in `data/cities.yml`
/// straddles it, and pretending to support it untested would be worse than
/// saying so here.
public struct BoundingBox: Sendable, Hashable, Codable {
    public var minLat: Double
    public var minLon: Double
    public var maxLat: Double
    public var maxLon: Double

    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    public var isValid: Bool {
        minLat <= maxLat && minLon <= maxLon
            && Coordinate(latitude: minLat, longitude: minLon).isValid
            && Coordinate(latitude: maxLat, longitude: maxLon).isValid
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    /// The smallest box holding both, used when a merged cluster spans more than
    /// one candidate position.
    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            minLat: Swift.min(minLat, other.minLat),
            minLon: Swift.min(minLon, other.minLon),
            maxLat: Swift.max(maxLat, other.maxLat),
            maxLon: Swift.max(maxLon, other.maxLon)
        )
    }
}
