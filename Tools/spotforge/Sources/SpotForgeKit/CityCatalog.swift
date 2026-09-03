import Foundation
import TDMCore

/// One district of a city: a sub-box Overpass is queried with.
///
/// Splitting a city keeps each query under the server's timeout, and the name
/// travels into the spot's tags so the UI can say "12 new spots in Brooklyn".
public struct DistrictDefinition: Sendable, Hashable {
    public var name: String
    public var bbox: BoundingBox

    public init(name: String, bbox: BoundingBox) {
        self.name = name
        self.bbox = bbox
    }
}

/// A city as declared in `data/cities.yml`.
public struct CityDefinition: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var country: String
    public var center: Coordinate
    public var bbox: BoundingBox
    public var districts: [DistrictDefinition]

    public init(
        id: String,
        name: String,
        country: String,
        center: Coordinate,
        bbox: BoundingBox,
        districts: [DistrictDefinition] = []
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.center = center
        self.bbox = bbox
        self.districts = districts
    }

    /// The boxes to fetch: the districts when there are any, the whole city
    /// otherwise. A city with no districts is small enough not to need them.
    public var queryBoxes: [DistrictDefinition] {
        districts.isEmpty ? [DistrictDefinition(name: name, bbox: bbox)] : districts
    }
}

public enum CityCatalogError: Error, CustomStringConvertible {
    case notASequence(path: String)
    case missingField(String, cityId: String)
    case invalidBoundingBox(cityId: String)
    case unknownCity(String, known: [String])

    public var description: String {
        switch self {
        case .notASequence(let path):
            "\(path): expected a sequence of cities."
        case let .missingField(field, cityId):
            "\(cityId): missing or malformed `\(field)`."
        case .invalidBoundingBox(let cityId):
            "\(cityId): the bounding box is not a box on Earth."
        case let .unknownCity(id, known):
            "no city `\(id)` in data/cities.yml. Known: \(known.joined(separator: ", "))."
        }
    }
}

/// `data/cities.yml`, decoded.
public struct CityCatalog: Sendable {
    public var cities: [CityDefinition]

    public init(cities: [CityDefinition]) {
        self.cities = cities
    }

    public static func load(contentsOf path: String) throws -> CityCatalog {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(text, path: path)
    }

    public static func parse(_ text: String, path: String = "data/cities.yml") throws -> CityCatalog {
        let root = try YAML.parse(text)
        guard let entries = root.sequenceValue else { throw CityCatalogError.notASequence(path: path) }
        return CityCatalog(cities: try entries.map(city(from:)))
    }

    public func city(withId id: String) throws -> CityDefinition {
        guard let city = cities.first(where: { $0.id == id }) else {
            throw CityCatalogError.unknownCity(id, known: cities.map(\.id))
        }
        return city
    }

    private static func city(from value: YAMLValue) throws -> CityDefinition {
        guard let id = value["id"]?.stringValue, !id.isEmpty else {
            throw CityCatalogError.missingField("id", cityId: "<unnamed>")
        }
        guard let name = value["name"]?.stringValue, !name.isEmpty else {
            throw CityCatalogError.missingField("name", cityId: id)
        }
        guard let country = value["country"]?.stringValue, !country.isEmpty else {
            throw CityCatalogError.missingField("country", cityId: id)
        }
        guard
            let centerValue = value["center"],
            let lat = centerValue["lat"]?.doubleValue,
            let lon = centerValue["lon"]?.doubleValue
        else {
            throw CityCatalogError.missingField("center", cityId: id)
        }
        guard let bbox = boundingBox(from: value["bbox"]) else {
            throw CityCatalogError.missingField("bbox", cityId: id)
        }
        guard bbox.isValid else { throw CityCatalogError.invalidBoundingBox(cityId: id) }

        var districts: [DistrictDefinition] = []
        for districtValue in value["districts"]?.sequenceValue ?? [] {
            guard
                let districtName = districtValue["name"]?.stringValue,
                let districtBox = boundingBox(from: districtValue["bbox"]),
                districtBox.isValid
            else {
                throw CityCatalogError.missingField("districts", cityId: id)
            }
            districts.append(DistrictDefinition(name: districtName, bbox: districtBox))
        }

        return CityDefinition(
            id: id,
            name: name,
            country: country,
            center: Coordinate(latitude: lat, longitude: lon),
            bbox: bbox,
            districts: districts
        )
    }

    static func boundingBox(from value: YAMLValue?) -> BoundingBox? {
        guard
            let value,
            let minLat = value["minLat"]?.doubleValue,
            let minLon = value["minLon"]?.doubleValue,
            let maxLat = value["maxLat"]?.doubleValue,
            let maxLon = value["maxLon"]?.doubleValue
        else { return nil }
        return BoundingBox(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
    }
}
