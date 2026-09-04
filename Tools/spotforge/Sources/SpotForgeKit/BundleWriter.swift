import Foundation
import TDMCore
import TDMSpots

/// Stage 7: gz + sha.
///
/// The JSON is canonical — sorted keys, pretty printed, ISO 8601 instants — so
/// a regenerated city is a reviewable diff and the published `sha256`, taken
/// over the *decompressed* bytes, is a function of the contents alone.
public struct BundleWriter: Sendable {
    public var outputDirectory: URL

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public struct WrittenBundle: Sendable {
        public var entry: CityIndexEntry
        public var jsonBytes: Int
        public var compressedBytes: Int
        public var bundleURL: URL
    }

    public var citiesDirectory: URL { outputDirectory.appendingPathComponent("cities") }
    public var indexURL: URL { outputDirectory.appendingPathComponent("index.json") }

    /// Writes `cities/{id}.json.gz` and returns the index row for it.
    public func write(_ city: City) throws -> WrittenBundle {
        let json = try BundleCoding.encoder().encode(city)
        let digest = SHA256.hexDigest(json)
        let compressed = GzipWriter.compress(json)

        try FileManager.default.createDirectory(at: citiesDirectory, withIntermediateDirectories: true)
        let url = citiesDirectory.appendingPathComponent("\(city.cityId).json.gz")
        try compressed.write(to: url)

        let entry = CityIndexEntry(
            cityId: city.cityId,
            name: city.name,
            country: city.country,
            lat: city.bbox.center.latitude,
            lon: city.bbox.center.longitude,
            bbox: city.bbox,
            spotCount: city.spots.count,
            bytes: compressed.count,
            sha256: digest,
            bundleVersion: city.bundleVersion,
            updatedAt: city.generatedAt
        )
        return WrittenBundle(
            entry: entry,
            jsonBytes: json.count,
            compressedBytes: compressed.count,
            bundleURL: url
        )
    }

    /// Rewrites `index.json`, keeping the rows for cities this run did not
    /// build. A one-city refresh must not delete the rest of the world.
    public func writeIndex(updating entries: [CityIndexEntry], generatedAt: Date) throws -> CityIndex {
        var rows = (try? readIndex())?.cities ?? []
        for entry in entries {
            if let existing = rows.firstIndex(where: { $0.cityId == entry.cityId }) {
                rows[existing] = entry
            } else {
                rows.append(entry)
            }
        }
        rows.sort { $0.cityId < $1.cityId }

        let index = CityIndex(generatedAt: generatedAt, cities: rows)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try BundleCoding.encoder().encode(index).write(to: indexURL)
        return index
    }

    public func readIndex() throws -> CityIndex {
        try BundleDecoder().decodeIndex(Data(contentsOf: indexURL))
    }

    /// The version the next build of this city publishes: one past whatever is
    /// on disk, so the client's "stored version is lower" test keeps working.
    public func nextBundleVersion(for cityId: String) -> Int {
        guard let index = try? readIndex(), let entry = index.entry(for: cityId) else { return 1 }
        return entry.bundleVersion + 1
    }
}
