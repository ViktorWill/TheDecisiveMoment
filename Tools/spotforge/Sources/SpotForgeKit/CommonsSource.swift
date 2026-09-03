import Foundation
import TDMCore

/// Wikimedia Commons photo density, and representative images for the spots
/// that end up at the top. `docs/SPOTFORGE.md` §4.
///
/// One query per candidate would be thousands of requests against a volunteer
/// service, so the city is swept once on a lattice and the results are binned
/// into the density grid. The actor keeps that grid: `fetch(bbox:)` fills it and
/// ``densityGrid()`` hands it to the scorer.
public actor CommonsSource: SpotSource {
    public static let endpoint = URL(string: "https://commons.wikimedia.org/w/api.php")!

    /// The API caps `gsradius` at 10 km and `gslimit` at 500 for anonymous
    /// clients. 500 m sample circles on a 500 m lattice cover the plane — the
    /// furthest a point can be from its nearest sample is 354 m — while keeping
    /// each response comfortably under the result limit in all but the densest
    /// parts of a city.
    public static let sampleRadiusMetres = 500.0
    public static let sampleSpacingMetres = 500.0

    public nonisolated let sourceKind: SourceKind = .commons

    private let runner: RequestRunner
    private let endpoint: URL
    private let cellMetres: Double
    /// A cell this photographed is a place even when no other source names it.
    private let minimumCellCountForCandidate: Int
    /// Sweeping a whole metropolitan bbox is thousands of requests; the ceiling
    /// makes an accidental continent-sized box fail loudly instead of running
    /// for a day against a volunteer service.
    private let maximumSamples: Int

    private var grid: PhotoDensityGrid?
    /// Sample circles overlap, so a file seen twice must be counted once.
    private var seenPageIds: Set<Int> = []
    public private(set) var sampleCount = 0

    public init(
        runner: RequestRunner,
        endpoint: URL = CommonsSource.endpoint,
        cellMetres: Double = 250,
        minimumCellCountForCandidate: Int = 25,
        maximumSamples: Int = 20_000
    ) {
        self.runner = runner
        self.endpoint = endpoint
        self.cellMetres = cellMetres
        self.minimumCellCountForCandidate = minimumCellCountForCandidate
        self.maximumSamples = maximumSamples
    }

    public func densityGrid() -> PhotoDensityGrid {
        grid ?? PhotoDensityGrid(cellMetres: cellMetres)
    }

    public func fetch(bbox: BoundingBox) async throws -> [RawSpot] {
        var grid = self.grid ?? PhotoDensityGrid(cellMetres: cellMetres, referenceLatitude: bbox.center.latitude)
        let points = grid.samplePoints(in: bbox, spacingMetres: Self.sampleSpacingMetres)
        guard points.count <= maximumSamples else {
            throw CommonsError.tooManySamples(points.count, limit: maximumSamples)
        }

        for point in points {
            let request = HTTPRequest(url: Self.geosearchURL(endpoint: endpoint, at: point))
            let data = try await runner.send(request, cacheNamespace: "commons")
            let response = try JSONDecoder().decode(GeosearchResponse.self, from: data)
            sampleCount += 1
            for file in response.query?.geosearch ?? [] where seenPageIds.insert(file.pageid).inserted {
                grid.add(Coordinate(latitude: file.lat, longitude: file.lon))
            }
        }
        self.grid = grid

        return grid.denseCells(minimumCount: minimumCellCountForCandidate).map { cell, count in
            RawSpot(
                source: .commons,
                sourceId: "cell/\(cell.latIndex)/\(cell.lonIndex)",
                coordinate: grid.center(of: cell),
                tags: ["photographed"],
                refs: ["commonsPhotos": String(count)]
            )
        }
    }

    /// Representative images for one coordinate, with author and licence.
    ///
    /// A photo that cannot be attributed is not returned at all: the bundle
    /// format requires both halves and the UI has to show them.
    public func photos(near coordinate: Coordinate, radiusMetres: Double = 200, limit: Int = 3) async throws -> [SpotPhoto] {
        let request = HTTPRequest(
            url: Self.imageInfoURL(endpoint: endpoint, at: coordinate, radiusMetres: radiusMetres, limit: limit)
        )
        let data = try await runner.send(request, cacheNamespace: "commons")
        let response = try JSONDecoder().decode(ImageInfoResponse.self, from: data)
        return (response.query?.pages ?? [:])
            .sorted { $0.key < $1.key }
            .compactMap { _, page in page.spotPhoto }
            .filter(\.isAttributed)
    }

    // MARK: - URLs

    /// `gsnamespace=6` is the part people get wrong: namespace 0 returns
    /// articles and the query looks broken.
    /// Five decimals is about a metre — finer than any of this warrants, and
    /// coarse enough that a merged coordinate whose last bit differs still
    /// hits the same cached response.
    static func coordinateParameter(_ coordinate: Coordinate) -> String {
        String(format: "%.5f|%.5f", coordinate.latitude, coordinate.longitude)
    }

    public static func geosearchURL(endpoint: URL = CommonsSource.endpoint, at coordinate: Coordinate) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "geosearch"),
            URLQueryItem(name: "gscoord", value: coordinateParameter(coordinate)),
            URLQueryItem(name: "gsradius", value: String(Int(sampleRadiusMetres))),
            URLQueryItem(name: "gsnamespace", value: "6"),
            URLQueryItem(name: "gslimit", value: "500"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        return components.url!
    }

    public static func imageInfoURL(
        endpoint: URL = CommonsSource.endpoint,
        at coordinate: Coordinate,
        radiusMetres: Double,
        limit: Int
    ) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "geosearch"),
            URLQueryItem(name: "ggscoord", value: coordinateParameter(coordinate)),
            URLQueryItem(name: "ggsradius", value: String(Int(max(10, radiusMetres)))),
            URLQueryItem(name: "ggsnamespace", value: "6"),
            URLQueryItem(name: "ggslimit", value: String(limit)),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "440"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        return components.url!
    }
}

public enum CommonsError: Error, CustomStringConvertible {
    case tooManySamples(Int, limit: Int)

    public var description: String {
        switch self {
        case let .tooManySamples(count, limit):
            "the Commons sweep would take \(count) requests, over the \(limit) allowed. Split the city into districts."
        }
    }
}

// MARK: - Wire format

struct GeosearchResponse: Decodable, Sendable {
    struct Query: Decodable, Sendable {
        var geosearch: [File]
    }

    struct File: Decodable, Sendable {
        var pageid: Int
        var title: String?
        var lat: Double
        var lon: Double
        var dist: Double?
    }

    var query: Query?
}

struct ImageInfoResponse: Decodable, Sendable {
    struct Query: Decodable, Sendable {
        /// `formatversion=2` returns an array; the legacy format returns a
        /// dictionary keyed by page id. Both are accepted, and both are keyed
        /// by page id here so the output order is stable.
        var pages: [Int: Page]?

        enum CodingKeys: String, CodingKey { case pages }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let list = try? container.decode([Page].self, forKey: .pages) {
                pages = Dictionary(
                    uniqueKeysWithValues: list.enumerated().map { offset, page in (page.pageid ?? offset, page) }
                )
            } else if let map = try? container.decode([String: Page].self, forKey: .pages) {
                pages = Dictionary(
                    uniqueKeysWithValues: map.map { key, page in (page.pageid ?? Int(key) ?? 0, page) }
                )
            } else {
                pages = nil
            }
        }
    }

    struct Page: Decodable, Sendable {
        var pageid: Int?
        var title: String?
        var imageinfo: [ImageInfo]?

        var spotPhoto: SpotPhoto? {
            guard let info = imageinfo?.first, let page = info.descriptionurl else { return nil }
            let author = info.extmetadata?["Artist"]?.value.map(HTML.plainText) ?? ""
            let license = info.extmetadata?["LicenseShortName"]?.value ?? ""
            return SpotPhoto(
                thumbURL: info.thumburl ?? info.url ?? "",
                pageURL: page,
                author: author,
                license: license
            )
        }
    }

    struct ImageInfo: Decodable, Sendable {
        var url: String?
        var thumburl: String?
        var descriptionurl: String?
        var extmetadata: [String: ExtMetadataValue]?
    }

    struct ExtMetadataValue: Decodable, Sendable {
        var value: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `extmetadata` values are usually strings but are occasionally
            // numbers, and one odd field must not lose a whole attribution.
            if let text = try? container.decode(String.self, forKey: .value) {
                value = text
            } else if let number = try? container.decode(Double.self, forKey: .value) {
                value = String(number)
            } else {
                value = nil
            }
        }

        enum CodingKeys: String, CodingKey { case value }
    }

    var query: Query?
}

/// `extmetadata.Artist` arrives as a fragment of HTML — usually a link to the
/// author's user page. The bundle stores text, so the markup comes off here
/// rather than in the app.
enum HTML {
    static func plainText(_ markup: String) -> String {
        var result = ""
        var insideTag = false
        for character in markup {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { result.append(character) }
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
