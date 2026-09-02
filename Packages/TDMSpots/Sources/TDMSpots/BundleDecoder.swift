import Foundation
import TDMCore

/// The one JSON configuration both halves of the schema use.
///
/// `spotforge` writes with this and the app reads with it, so a bundle is a
/// byte-for-byte function of its contents: sorted keys and pretty printing make
/// a regenerated city a reviewable diff rather than a wall of one line, and
/// unescaped slashes keep the Commons URLs readable.
public enum BundleCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Why a bundle was refused. Every case names the city, because "checksum
/// mismatch" on its own tells the user nothing they can act on.
public enum BundleError: Error, Equatable, Sendable, CustomStringConvertible {
    case decompressionFailed(cityId: String, reason: String)
    /// The SHA-256 over the decompressed JSON did not match `index.json`.
    /// The file is discarded whole — partial data is worse than none.
    case checksumMismatch(cityId: String, expected: String, actual: String)
    case unsupportedSchemaVersion(cityId: String, found: Int, supported: Int)
    /// The bundle is for a different city than the index entry it was fetched
    /// for, which means a mixed-up path or a stale CDN cache.
    case cityIdMismatch(expected: String, found: String)
    case malformedJSON(cityId: String, reason: String)
    case sizeMismatch(cityId: String, expected: Int, actual: Int)

    public var description: String {
        switch self {
        case let .decompressionFailed(cityId, reason):
            "\(cityId): the downloaded bundle could not be decompressed (\(reason))."
        case let .checksumMismatch(cityId, expected, actual):
            "\(cityId): checksum mismatch — expected \(expected), got \(actual). The download was discarded."
        case let .unsupportedSchemaVersion(cityId, found, supported):
            "\(cityId): bundle schema v\(found), this build reads v\(supported)."
        case let .cityIdMismatch(expected, found):
            "expected the bundle for \(expected) but it contains \(found)."
        case let .malformedJSON(cityId, reason):
            "\(cityId): the bundle is not valid JSON for this schema (\(reason))."
        case let .sizeMismatch(cityId, expected, actual):
            "\(cityId): downloaded \(actual) bytes, the index says \(expected)."
        }
    }
}

/// Decompress, verify, decode — in that order, and all-or-nothing.
///
/// The verification is the point: a truncated download that decoded to half a
/// city would leave the map quietly missing places, which is indistinguishable
/// in the field from those places not existing.
public struct BundleDecoder: Sendable {
    /// Whether to check the compressed size against `index.json`. On by default;
    /// the checksum is the real guarantee, this only reports the failure sooner.
    public var verifiesCompressedSize: Bool

    public init(verifiesCompressedSize: Bool = true) {
        self.verifiesCompressedSize = verifiesCompressedSize
    }

    /// The whole client path for one city: gzip in, `City` out.
    public func decodeCity(compressed data: Data, entry: CityIndexEntry) throws -> City {
        if verifiesCompressedSize, entry.bytes > 0, data.count != entry.bytes {
            throw BundleError.sizeMismatch(cityId: entry.cityId, expected: entry.bytes, actual: data.count)
        }

        let json: Data
        do {
            json = try Gzip.decompress(data)
        } catch {
            throw BundleError.decompressionFailed(cityId: entry.cityId, reason: String(describing: error))
        }

        return try decodeCity(json: json, expectedSHA256: entry.sha256, expectedCityId: entry.cityId)
    }

    /// Decoded from decompressed JSON. `expectedSHA256` is over exactly these
    /// bytes — the decompressed form — which is what `index.json` publishes.
    public func decodeCity(json: Data, expectedSHA256: String? = nil, expectedCityId: String? = nil) throws -> City {
        let cityId = expectedCityId ?? "unknown city"

        if let expectedSHA256 {
            let actual = SHA256.hexDigest(json)
            guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw BundleError.checksumMismatch(
                    cityId: cityId,
                    expected: expectedSHA256.lowercased(),
                    actual: actual
                )
            }
        }

        let city: City
        do {
            city = try BundleCoding.decoder().decode(City.self, from: json)
        } catch {
            throw BundleError.malformedJSON(cityId: cityId, reason: String(describing: error))
        }

        guard city.schemaVersion == TDMSpots.supportedBundleSchemaVersion else {
            throw BundleError.unsupportedSchemaVersion(
                cityId: city.cityId,
                found: city.schemaVersion,
                supported: TDMSpots.supportedBundleSchemaVersion
            )
        }
        if let expectedCityId, city.cityId != expectedCityId {
            throw BundleError.cityIdMismatch(expected: expectedCityId, found: city.cityId)
        }

        return city
    }

    public func decodeIndex(_ data: Data) throws -> CityIndex {
        let index: CityIndex
        do {
            index = try BundleCoding.decoder().decode(CityIndex.self, from: data)
        } catch {
            throw BundleError.malformedJSON(cityId: "index", reason: String(describing: error))
        }
        guard index.schemaVersion == TDMSpots.supportedBundleSchemaVersion else {
            throw BundleError.unsupportedSchemaVersion(
                cityId: "index",
                found: index.schemaVersion,
                supported: TDMSpots.supportedBundleSchemaVersion
            )
        }
        return index
    }

    /// Whether a stored city needs replacing. Version-based rather than
    /// timestamp-based so a clock skew never triggers a download on roaming.
    public func needsDownload(entry: CityIndexEntry, storedBundleVersion: Int?) -> Bool {
        guard let storedBundleVersion else { return true }
        return storedBundleVersion < entry.bundleVersion
    }
}
