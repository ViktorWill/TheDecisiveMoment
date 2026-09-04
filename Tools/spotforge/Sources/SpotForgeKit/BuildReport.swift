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

    /// How long one named stage of the pipeline took. An array, not a
    /// dictionary keyed by name, so the report reads in the order the stages
    /// actually ran rather than however a dictionary happens to iterate.
    public struct StageDuration: Sendable {
        public var stage: String
        public var seconds: Double
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
    /// The budget ``compressedBytes`` is judged against, carried here so the
    /// warning can name both numbers — `PipelineOptions.sizeBudgetBytes`.
    public var sizeBudgetBytes = 0
    public var requestCount = 0
    public var cacheHitCount = 0
    public var stageDurations: [StageDuration] = []

    public init(cityId: String) {
        self.cityId = cityId
    }

    /// Records how long a stage took, measured from `since` to now. Called
    /// once per stage so the final report can say where the time actually
    /// went — PR #16: an hour-long merge and a genuine hang looked
    /// identical without this.
    public mutating func recordStage(_ stage: String, since started: Date) {
        stageDurations.append(StageDuration(stage: stage, seconds: Date().timeIntervalSince(started)))
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
        if isOverSizeBudget {
            warnings.append("the bundle is \(compressedBytes) B gz, over the \(sizeBudgetBytes) B budget by \(compressedBytes - sizeBudgetBytes) B.")
        }
        return warnings
    }

    /// Whether the bundle actually written missed its budget. Zero means the
    /// size was never measured — a report built without a write — rather than
    /// a budget of nothing, so it cannot warn.
    public var isOverSizeBudget: Bool {
        sizeBudgetBytes > 0 && compressedBytes > sizeBudgetBytes
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
        if !stageDurations.isEmpty {
            let stages = stageDurations.map { "\($0.stage) \(String(format: "%.1f", $0.seconds))s" }.joined(separator: ", ")
            lines.append("  elapsed    \(stages)")
        }
        for warning in warnings {
            lines.append("  ! \(warning)")
        }
        return lines.joined(separator: "\n")
    }
}
