import Foundation
import TDMCore

/// GeoJSON export of the user's own pins, `docs/SPEC-map.md` ("Your own pins").
///
/// The point is that the data is never trapped: pins are local-only in v1, so
/// the only way out of the device is a file the user can open in anything.
/// RFC 7946 — `[longitude, latitude]`, in that order, which is the reverse of
/// how the rest of this codebase writes a coordinate and is the single most
/// likely mistake here.
public enum GeoJSONExport {
    /// A `FeatureCollection` of pins, written with the bundle's canonical JSON
    /// formatting so an exported file is diffable and stable.
    public static func featureCollection(_ spots: [Spot]) throws -> Data {
        let collection = FeatureCollection(features: spots.map(Feature.init))
        return try BundleCoding.encoder().encode(collection)
    }

    /// A file name that sorts by date and says what it is.
    public static func fileName(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "the-decisive-moment-pins-%04d-%02d-%02d.geojson", year, month, day)
    }

    struct FeatureCollection: Codable {
        var type = "FeatureCollection"
        var features: [Feature]
    }

    struct Feature: Codable {
        var type = "Feature"
        var geometry: Point
        var properties: Properties

        init(_ spot: Spot) {
            geometry = Point(coordinates: [spot.lon, spot.lat])
            properties = Properties(spot)
        }
    }

    struct Point: Codable {
        var type = "Point"
        /// `[longitude, latitude]`, RFC 7946 §3.1.1.
        var coordinates: [Double]
    }

    struct Properties: Codable {
        var id: String
        var name: String
        var kind: String
        var openness: String
        var tags: [String]
        var note: String?
        var streetBearing: Double?
        var curated: Bool

        init(_ spot: Spot) {
            id = spot.id
            name = spot.name
            kind = spot.kind.rawValue
            openness = spot.openness.rawValue
            tags = spot.tags
            note = spot.note
            streetBearing = spot.streetBearing
            curated = spot.curated
        }
    }
}
