import Foundation
import TDMCore

/// What a build did, in the terms the operator needs — `docs/SPOTFORGE.md` §1.
///
/// A source silently returning nothing is the most likely failure mode in this
/// pipeline, so it is not merely counted: ``warnings`` names it and the CLI
/// exits non-zero when `--strict` is set.
public struct BuildReport: Sendable {
    public struct SourceTally: Sendable {
        public var source: SourceKind
        public var candidates: Int
        /// A source that failed outright, rather than one that returned nothing.
        public var failure: String?
    }

    public var cityId: String
    public var sources: [SourceTally] = []
    public var candidateCount = 0
    public var mergedCount = 0
    public var droppedBySizeCap = 0
    public var scoreFloor: Double?
    public var photoCells = 0
    public var photoTotal = 0
    public var spotCount = 0
    public var jsonBytes = 0
    public var compressedBytes = 0
    public var requestCount = 0
    public var cacheHitCount = 0

    public init(cityId: String) {
        self.cityId = cityId
    }

    /// Merges performed: how many candidates the dedupe pass collapsed.
    public var merges: Int { max(0, candidateCount - mergedCount) }

    public var emptySources: [SourceKind] {
        sources.filter { $0.candidates == 0 && $0.failure == nil }.map(\.source)
    }

    public var failedSources: [SourceKind] {
        sources.filter { $0.failure != nil }.map(\.source)
    }

    public var warnings: [String] {
        var warnings: [String] = []
        for tally in sources {
            if let failure = tally.failure {
                warnings.append("\(tally.source.rawValue) failed: \(failure)")
            } else if tally.candidates == 0 {
                warnings.append("\(tally.source.rawValue) returned nothing — that is almost always a bug, not a city.")
            }
        }
        if spotCount == 0 {
            warnings.append("the bundle has no spots at all.")
        }
        return warnings
    }

    public var summary: String {
        var lines = ["spotforge \(cityId)"]
        for tally in sources {
            let detail = tally.failure.map { "failed — \($0)" } ?? "\(tally.candidates) candidates"
            lines.append("  \(tally.source.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(detail)")
        }
        lines.append("  candidates \(candidateCount) → merged \(mergedCount) (\(merges) merges)")
        lines.append("  photos     \(photoTotal) geotagged files in \(photoCells) cells")
        if droppedBySizeCap > 0, let floor = scoreFloor {
            lines.append("  size cap   dropped \(droppedBySizeCap) below score \(String(format: "%.3f", floor))")
        } else {
            lines.append("  size cap   nothing dropped")
        }
        lines.append("  written    \(spotCount) spots, \(compressedBytes) B gz (\(jsonBytes) B json)")
        lines.append("  network    \(requestCount) requests, \(cacheHitCount) cache hits")
        for warning in warnings {
            lines.append("  ! \(warning)")
        }
        return lines.joined(separator: "\n")
    }
}
