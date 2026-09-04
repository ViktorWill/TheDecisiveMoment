import Foundation
import TDMCore

/// OpenStreetMap through Overpass — the backbone of the pipeline, and what
/// makes a city the app has never seen still be useful. `docs/SPOTFORGE.md` §2.
///
/// The usage policy is not decoration: Overpass is volunteer-run, so every call
/// goes through the shared ``RequestRunner``, which serialises requests, caches
/// them under `.cache/overpass/` and identifies the client.
public struct OverpassSource: SpotSource {
    public static let primaryEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    public static let fallbackEndpoint = URL(string: "https://overpass.kumi.systems/api/interpreter")!

    /// Metres per storey, for turning `building:levels` into a height. The OSM
    /// wiki's own rule of thumb; only ever used to decide `canyon`, and the
    /// threshold is high enough that the exact figure does not matter.
    static let metresPerLevel = 3.1
    /// A building this close counts toward the street's walls.
    static let canyonRadiusMetres = 30.0
    /// Mean wall height above which a street is a canyon. Conservative on
    /// purpose: a wrong `canyon` costs the user 3.5 stops.
    static let canyonHeightMetres = 25.0

    public let sourceKind: SourceKind = .osm
    private let runner: RequestRunner
    private let endpoints: [URL]
    /// Off for a quick build: it doubles the number of Overpass queries.
    private let inspectsBuildingHeights: Bool

    public init(
        runner: RequestRunner,
        endpoints: [URL] = [primaryEndpoint, fallbackEndpoint],
        inspectsBuildingHeights: Bool = true
    ) {
        self.runner = runner
        self.endpoints = endpoints
        self.inspectsBuildingHeights = inspectsBuildingHeights
    }

    public func fetch(bbox: BoundingBox) async throws -> [RawSpot] {
        let response = try await run(query: Self.featureQuery(bbox: bbox))
        let buildings = inspectsBuildingHeights
            ? (try? await run(query: Self.buildingQuery(bbox: bbox)))?.elements ?? []
            : []
        let walls = BuildingHeightIndex(elements: buildings)
        return Self.joined(response.elements).compactMap { element in
            spot(from: element, walls: walls)
        }
    }

    /// The two `out` statements return each element twice — once with tags and
    /// a centre, once with its node list. Join them back into one record, in
    /// the order Overpass first mentioned each element so the result is stable.
    static func joined(_ elements: [OverpassElement]) -> [OverpassElement] {
        var order: [String] = []
        var merged: [String: OverpassElement] = [:]
        for element in elements {
            let key = "\(element.type)/\(element.id)"
            guard var existing = merged[key] else {
                order.append(key)
                merged[key] = element
                continue
            }
            if existing.tags == nil { existing.tags = element.tags }
            if existing.lat == nil { existing.lat = element.lat }
            if existing.lon == nil { existing.lon = element.lon }
            if existing.center == nil { existing.center = element.center }
            if existing.geometry == nil { existing.geometry = element.geometry }
            merged[key] = existing
        }
        return order.compactMap { merged[$0] }
    }

    /// Tries each endpoint in order. A single volunteer server being down is not
    /// a reason to lose a month's refresh.
    private func run(query: String) async throws -> OverpassResponse {
        var lastError: (any Error)?
        for endpoint in endpoints {
            do {
                let request = HTTPRequest(
                    url: endpoint,
                    method: "POST",
                    body: Data(query.utf8),
                    headers: ["Content-Type": "text/plain; charset=utf-8"]
                )
                let data = try await runner.send(request, cacheNamespace: "overpass")
                return try JSONDecoder().decode(OverpassResponse.self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? HTTPError.offline(url: endpoints[0])
    }

    // MARK: - Queries

    static func bboxClause(_ bbox: BoundingBox) -> String {
        "\(bbox.minLat),\(bbox.minLon),\(bbox.maxLat),\(bbox.maxLon)"
    }

    /// The `highway` values a covered or tunnelled way must carry to qualify —
    /// places people actually walk, not a vehicle underpass or service road
    /// swept in by a bare `["highway"]` presence check.
    static let walkableHighwayPattern = "^(pedestrian|footway|steps|path)$"

    /// The §2 query. Two `out` statements over one stored result set: Overpass
    /// allows only one geometry mode per `out`, so `center` gives the map its
    /// representative coordinate and a second, id-only `geom` pass gives the
    /// node list that `streetBearing` is derived from.
    public static func featureQuery(bbox: BoundingBox) -> String {
        let box = bboxClause(bbox)
        return """
        [out:json][timeout:180];
        (
          node["highway"="pedestrian"](\(box));
          way ["highway"="pedestrian"](\(box));
          way ["highway"="footway"]["footway"="crossing"]["crossing"="traffic_signals"](\(box));
          node["amenity"="marketplace"](\(box));
          way ["amenity"="marketplace"](\(box));
          way ["place"="square"](\(box));
          node["place"="square"](\(box));
          way ["man_made"="bridge"](\(box));
          way ["highway"="steps"]["name"](\(box));
          way ["tunnel"="yes"]["highway"~"\(walkableHighwayPattern)"](\(box));
          way ["covered"="yes"]["highway"~"\(walkableHighwayPattern)"](\(box));
          node["tourism"="viewpoint"](\(box));
          node["railway"="station"](\(box));
          node["public_transport"="station"](\(box));
          way ["leisure"="park"](\(box));
          way ["natural"="coastline"](\(box));
        )->.spots;
        .spots out center tags;
        .spots out ids geom;
        """
    }

    /// Buildings that declare a height, for the `canyon` reading. Ids, centre
    /// and the two tags that matter — nothing else, because this box can hold
    /// tens of thousands of buildings.
    public static func buildingQuery(bbox: BoundingBox) -> String {
        let box = bboxClause(bbox)
        return """
        [out:json][timeout:180];
        (
          way["building"]["building:levels"](\(box));
          way["building"]["height"](\(box));
        );
        out center tags;
        """
    }

    // MARK: - Mapping

    func spot(from element: OverpassElement, walls: BuildingHeightIndex) -> RawSpot? {
        guard let coordinate = element.coordinate, coordinate.isValid else { return nil }
        let tags = element.tags ?? [:]
        guard !tags.isEmpty else { return nil }

        let kind = Self.kind(for: tags, isArea: element.isArea)
        let openness = Self.openness(for: tags, at: coordinate, walls: walls)
        let bearing = element.geometry.flatMap { nodes -> Double? in
            guard let first = nodes.first, let last = nodes.last, first != last else { return nil }
            return Geometry.normalisedBearing(
                Geometry.bearing(
                    from: Coordinate(latitude: first.lat, longitude: first.lon),
                    to: Coordinate(latitude: last.lat, longitude: last.lon)
                )
            )
        }

        let reference = "\(element.type)/\(element.id)"
        var refs = ["osm": reference]
        if let wikidata = tags["wikidata"] { refs["wikidata"] = wikidata }

        return RawSpot(
            source: .osm,
            sourceId: reference,
            name: tags["name"] ?? tags["name:en"] ?? "",
            coordinate: coordinate,
            kind: kind,
            tags: Self.descriptiveTags(for: tags),
            openness: openness,
            streetBearing: bearing,
            refs: refs
        )
    }

    /// The §2 tag table, most specific first.
    static func kind(for tags: [String: String], isArea: Bool) -> SpotKind {
        if tags["amenity"] == "marketplace" { return .market }
        if tags["place"] == "square" { return .plaza }
        if tags["highway"] == "steps" { return .stairs }
        if tags["tunnel"] == "yes" { return .underpass }
        if tags["covered"] == "yes" || tags["building"] == "arcade" { return .arcade }
        if tags["man_made"] == "bridge" || tags["bridge"] == "yes" { return .bridge }
        if tags["railway"] == "station" || tags["public_transport"] == "station" { return .transit }
        if tags["natural"] == "coastline" || tags["waterway"] != nil { return .waterfront }
        if tags["tourism"] == "viewpoint" { return .viewpoint }
        if tags["leisure"] == "park" { return .park }
        if tags["highway"] == "pedestrian" { return isArea ? .plaza : .street }
        if tags["highway"] == "footway", tags["footway"] == "crossing" { return .intersection }
        return .other
    }

    /// `covered` is a tag and therefore certain; `canyon` is inferred from the
    /// buildings around the point and is only claimed when the walls really are
    /// high, because over-claiming it costs the user 3.5 stops.
    static func openness(
        for tags: [String: String],
        at coordinate: Coordinate,
        walls: BuildingHeightIndex
    ) -> Openness {
        if tags["tunnel"] == "yes" || tags["covered"] == "yes" || tags["building"] == "arcade" {
            return .covered
        }
        if let mean = walls.meanHeight(around: coordinate, radiusMetres: canyonRadiusMetres),
           mean > canyonHeightMetres {
            return .canyon
        }
        return .open
    }

    /// Free-form, lowercase, and only what a person would recognise: the tag
    /// dump is not useful in a filter pill.
    static func descriptiveTags(for tags: [String: String]) -> [String] {
        var result: Set<String> = []
        for key in ["amenity", "leisure", "place", "highway", "railway", "tourism", "man_made", "natural"] {
            if let value = tags[key], value != "yes" { result.insert(value.lowercased()) }
        }
        if tags["covered"] == "yes" { result.insert("covered") }
        if tags["tunnel"] == "yes" { result.insert("tunnel") }
        if tags["bridge"] == "yes" { result.insert("bridge") }
        return result.sorted()
    }
}

/// Buildings that declare a height, bucketed so the canyon test is a lookup
/// rather than a scan over every building in the city.
struct BuildingHeightIndex: Sendable {
    /// ~0.001° of latitude is about 111 m, comfortably more than the 30 m probe.
    private static let cellDegrees = 0.001
    private var cells: [Cell: [(coordinate: Coordinate, height: Double)]] = [:]

    struct Cell: Hashable {
        var latIndex: Int
        var lonIndex: Int
    }

    init(elements: [OverpassElement]) {
        for element in elements {
            guard
                let coordinate = element.coordinate,
                coordinate.isValid,
                let height = Self.height(of: element.tags ?? [:])
            else { continue }
            cells[Self.cell(for: coordinate), default: []].append((coordinate, height))
        }
    }

    static func height(of tags: [String: String]) -> Double? {
        if let height = tags["height"].flatMap(Self.metres), height > 0 { return height }
        if let levels = tags["building:levels"].flatMap(Double.init), levels > 0 {
            return levels * OverpassSource.metresPerLevel
        }
        return nil
    }

    /// OSM heights are metres by convention, but the unit is sometimes written
    /// out, and `12 m` parsed as nothing would quietly lose a wall.
    static func metres(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let plain = Double(trimmed) { return plain }
        if trimmed.hasSuffix("m") { return Double(trimmed.dropLast().trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func cell(for coordinate: Coordinate) -> Cell {
        Cell(
            latIndex: Int((coordinate.latitude / cellDegrees).rounded(.down)),
            lonIndex: Int((coordinate.longitude / cellDegrees).rounded(.down))
        )
    }

    /// The mean height of the buildings within `radiusMetres`, or `nil` when
    /// there are none to speak of — silence rather than a guess.
    func meanHeight(around coordinate: Coordinate, radiusMetres: Double) -> Double? {
        let origin = Self.cell(for: coordinate)
        var total = 0.0
        var count = 0
        for latOffset in -1...1 {
            for lonOffset in -1...1 {
                let cell = Cell(latIndex: origin.latIndex + latOffset, lonIndex: origin.lonIndex + lonOffset)
                for building in cells[cell] ?? []
                where building.coordinate.distance(to: coordinate) <= radiusMetres {
                    total += building.height
                    count += 1
                }
            }
        }
        guard count >= 2 else { return nil }
        return total / Double(count)
    }
}

// MARK: - Wire format

public struct OverpassResponse: Decodable, Sendable {
    public var elements: [OverpassElement]
}

public struct OverpassElement: Decodable, Sendable {
    public struct Point: Decodable, Sendable, Equatable {
        public var lat: Double
        public var lon: Double
    }

    public var type: String
    public var id: Int
    public var lat: Double?
    public var lon: Double?
    public var center: Point?
    public var geometry: [Point]?
    public var tags: [String: String]?

    /// `out center` gives ways a `center`; nodes carry their own position.
    public var coordinate: Coordinate? {
        if let lat, let lon { return Coordinate(latitude: lat, longitude: lon) }
        if let center { return Coordinate(latitude: center.lat, longitude: center.lon) }
        if let geometry, let first = geometry.first {
            return Coordinate(latitude: first.lat, longitude: first.lon)
        }
        return nil
    }

    /// A closed way is an area; `highway=pedestrian` as an area is a plaza and
    /// as a line is a street, which is a real difference to stand in.
    public var isArea: Bool {
        if type != "way" { return false }
        if tags?["area"] == "yes" { return true }
        guard let geometry, geometry.count > 2 else { return false }
        return geometry.first == geometry.last
    }
}
