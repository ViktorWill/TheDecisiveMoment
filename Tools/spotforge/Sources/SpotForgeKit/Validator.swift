import Foundation
import TDMCore
import TDMSpots

/// `spotforge validate bundles/v1` — decode everything the way the app would.
///
/// The point is that the check is the client's own path: `BundleDecoder`
/// decompresses, verifies the SHA-256 over the decompressed JSON against
/// `index.json`, and decodes with the schema the app links. A bundle that
/// passes here cannot fail on a phone for a reason this tool could have seen.
public struct BundleValidator: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public struct Result: Sendable {
        public var cities: [String] = []
        public var spotCount = 0
        public var problems: [String] = []
        public var isValid: Bool { problems.isEmpty }

        public var summary: String {
            var lines: [String] = []
            for city in cities {
                lines.append("  ok  \(city)")
            }
            for problem in problems {
                lines.append("  !!  \(problem)")
            }
            lines.append(
                problems.isEmpty
                    ? "\(cities.count) cities, \(spotCount) spots, every hash matched."
                    : "\(problems.count) problem(s) found."
            )
            return lines.joined(separator: "\n")
        }
    }

    public func validate() -> Result {
        var result = Result()
        let indexURL = directory.appendingPathComponent("index.json")

        let index: CityIndex
        do {
            index = try BundleDecoder().decodeIndex(try Data(contentsOf: indexURL))
        } catch {
            result.problems.append("index.json: \(error)")
            return result
        }

        if index.cities.isEmpty {
            result.problems.append("index.json lists no cities.")
        }

        for entry in index.cities {
            guard entry.isValid else {
                result.problems.append("\(entry.cityId): the index row is malformed.")
                continue
            }
            let bundleURL = directory.appendingPathComponent(entry.bundlePath)
            guard let compressed = try? Data(contentsOf: bundleURL) else {
                result.problems.append("\(entry.cityId): \(entry.bundlePath) is missing.")
                continue
            }
            do {
                let city = try BundleDecoder().decodeCity(compressed: compressed, entry: entry)
                guard city.isValid else {
                    result.problems.append("\(entry.cityId): a decoded spot is not valid.")
                    continue
                }
                guard city.spots.count == entry.spotCount else {
                    result.problems.append(
                        "\(entry.cityId): the index says \(entry.spotCount) spots, the bundle holds \(city.spots.count)."
                    )
                    continue
                }
                result.cities.append("\(entry.cityId) — \(city.spots.count) spots, \(entry.bytes) B")
                result.spotCount += city.spots.count
            } catch {
                result.problems.append("\(entry.cityId): \(error)")
            }
        }

        return result
    }
}
