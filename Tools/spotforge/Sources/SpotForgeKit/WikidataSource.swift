import Foundation
import TDMCore

/// Wikidata through WDQS: the "famous places" layer, and the only source of the
/// notability signal. `docs/SPOTFORGE.md` §3.
///
/// `sitelinks` — the number of Wikipedia language editions with an article — is
/// crude, but it is robust and it does not need a key.
public struct WikidataSource: SpotSource {
    public static let endpoint = URL(string: "https://query.wikidata.org/sparql")!

    public let sourceKind: SourceKind = .wikidata
    private let runner: RequestRunner
    private let endpoint: URL
    /// Below this many language editions a place is not "notable", it is merely
    /// present, and the layer stops being the famous-places layer.
    private let minimumSitelinks: Int

    public init(runner: RequestRunner, endpoint: URL = WikidataSource.endpoint, minimumSitelinks: Int = 5) {
        self.runner = runner
        self.endpoint = endpoint
        self.minimumSitelinks = minimumSitelinks
    }

    public func fetch(bbox: BoundingBox) async throws -> [RawSpot] {
        let query = Self.query(bbox: bbox, minimumSitelinks: minimumSitelinks)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components?.url else { throw HTTPError.offline(url: endpoint) }

        let request = HTTPRequest(
            url: url,
            headers: ["Accept": "application/sparql-results+json"]
        )
        let data = try await runner.send(request, cacheNamespace: "wikidata")
        let response = try JSONDecoder().decode(SPARQLResponse.self, from: data)
        return response.results.bindings.compactMap(Self.spot(from:))
    }

    public static func query(bbox: BoundingBox, minimumSitelinks: Int = 5) -> String {
        """
        SELECT ?item ?itemLabel ?coord ?sitelinks WHERE {
          SERVICE wikibase:box {
            ?item wdt:P625 ?coord .
            bd:serviceParam wikibase:cornerSouthWest "Point(\(bbox.minLon) \(bbox.minLat))"^^geo:wktLiteral .
            bd:serviceParam wikibase:cornerNorthEast "Point(\(bbox.maxLon) \(bbox.maxLat))"^^geo:wktLiteral .
          }
          ?item wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks > \(minimumSitelinks))
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
        }
        """
    }

    static func spot(from binding: [String: SPARQLValue]) -> RawSpot? {
        guard
            let item = binding["item"]?.value,
            let qid = item.split(separator: "/").last.map(String.init),
            let literal = binding["coord"]?.value,
            let point = parsePoint(literal),
            point.isValid
        else { return nil }

        let sitelinks = (binding["sitelinks"]?.value).flatMap { Int($0) }
        let label = binding["itemLabel"]?.value ?? ""
        // WDQS falls back to the Q-id when no English label exists, and a spot
        // called "Q42" on a map is worse than an unnamed one.
        let name = label == qid ? "" : label

        return RawSpot(
            source: .wikidata,
            sourceId: qid,
            name: name,
            coordinate: point,
            // Wikidata says a place is notable, not what it is like to stand
            // in. `landmark` is the honest default, and it scores low on
            // purpose — a monument is not a street photography spot.
            kind: .landmark,
            refs: ["wikidata": qid],
            sitelinks: sitelinks
        )
    }

    /// `Point(lon lat)` in WKT — longitude first, which is the reverse of every
    /// other coordinate in this codebase and the easiest bug to write.
    static func parsePoint(_ literal: String) -> Coordinate? {
        guard
            let open = literal.firstIndex(of: "("),
            let close = literal.lastIndex(of: ")"),
            open < close
        else { return nil }
        let numbers = literal[literal.index(after: open)..<close]
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double(String($0)) }
        guard numbers.count == 2 else { return nil }
        return Coordinate(latitude: numbers[1], longitude: numbers[0])
    }
}

// MARK: - Wire format

/// SPARQL 1.1 Query Results JSON.
public struct SPARQLResponse: Decodable, Sendable {
    public struct Results: Decodable, Sendable {
        public var bindings: [[String: SPARQLValue]]
    }

    public var results: Results
}

public struct SPARQLValue: Decodable, Sendable {
    public var type: String?
    /// Always present in SPARQL 1.1 JSON results; a binding without one is not
    /// a binding.
    public var value: String
    public var datatype: String?
}
