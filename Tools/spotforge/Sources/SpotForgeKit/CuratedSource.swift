import Foundation
import TDMCore

/// The hand-written canon, `data/curated/{cityId}.yml` — `docs/SPOTFORGE.md` §5.
///
/// It is the only source that is not a network call, and the only one whose
/// entries the size cap may not drop. Ten good entries per city beat a thousand
/// generated ones.
public struct CuratedSource: SpotSource {
    public let sourceKind: SourceKind = .curated
    private let cityId: String
    private let path: String
    /// A missing file is normal for a city nobody has written up yet; a
    /// malformed one is not, and raises.
    private let isOptional: Bool

    public init(cityId: String, directory: String = "data/curated", isOptional: Bool = true) {
        self.cityId = cityId
        self.path = "\(directory)/\(cityId).yml"
        self.isOptional = isOptional
    }

    public func fetch(bbox: BoundingBox) async throws -> [RawSpot] {
        guard FileManager.default.fileExists(atPath: path) else {
            if isOptional { return [] }
            throw CuratedError.missingFile(path: path)
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try Self.parse(text, cityId: cityId, path: path)
            .filter { bbox.contains($0.coordinate) }
    }

    public static func parse(_ text: String, cityId: String, path: String = "<curated>") throws -> [RawSpot] {
        let root = try YAML.parse(text)
        guard let entries = root.sequenceValue else { throw CuratedError.notASequence(path: path) }
        var slugs: Set<String> = []
        return try entries.map { entry in
            guard let name = entry["name"]?.stringValue, !name.isEmpty else {
                throw CuratedError.missingField("name", path: path)
            }
            guard let lat = entry["lat"]?.doubleValue, let lon = entry["lon"]?.doubleValue else {
                throw CuratedError.missingField("lat/lon for \(name)", path: path)
            }
            let coordinate = Coordinate(latitude: lat, longitude: lon)
            guard coordinate.isValid else { throw CuratedError.invalidCoordinate(name: name, path: path) }

            let slug = entry["slug"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? Self.slug(from: name)
            guard slugs.insert(slug).inserted else { throw CuratedError.duplicateSlug(slug, path: path) }

            let kind = entry["kind"]?.stringValue.flatMap(SpotKind.init(rawValue:)) ?? .other
            let openness = entry["openness"]?.stringValue.flatMap(Openness.init(rawValue:)) ?? .open
            let tags = entry["tags"]?.sequenceValue?.compactMap { $0.stringValue?.lowercased() } ?? []
            let hours = entry["bestHours"]?.sequenceValue?.compactMap(\.intValue)
            let note = entry["note"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }

            return RawSpot(
                source: .curated,
                sourceId: "\(cityId)/\(slug)",
                name: name,
                coordinate: coordinate,
                kind: kind,
                tags: tags,
                openness: openness,
                streetBearing: entry["streetBearing"]?.doubleValue,
                bestHours: hours?.isEmpty == false ? hours : nil,
                note: note,
                refs: ["curated": "\(cityId)/\(slug)"],
                curationBoost: entry["score_boost"]?.doubleValue ?? 0,
                curationNote: "\(cityId) canon"
            )
        }
    }

    /// The id half of a curated entry, and therefore stable: renaming an entry
    /// without setting `slug` breaks the join to a user's favourites, which is
    /// why `slug` exists at all.
    static func slug(from name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        var previousWasSeparator = false
        for character in folded {
            if character.isLetter || character.isNumber {
                result.append(Character(character.lowercased()))
                previousWasSeparator = false
            } else if !previousWasSeparator, !result.isEmpty {
                result.append("-")
                previousWasSeparator = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }
}

public enum CuratedError: Error, CustomStringConvertible {
    case missingFile(path: String)
    case notASequence(path: String)
    case missingField(String, path: String)
    case invalidCoordinate(name: String, path: String)
    case duplicateSlug(String, path: String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            "\(path): no curated file."
        case .notASequence(let path):
            "\(path): expected a sequence of entries."
        case let .missingField(field, path):
            "\(path): missing \(field)."
        case let .invalidCoordinate(name, path):
            "\(path): \(name) is not at a position on Earth — check for a swapped lat/lon."
        case let .duplicateSlug(slug, path):
            "\(path): two entries share the slug `\(slug)`."
        }
    }
}
