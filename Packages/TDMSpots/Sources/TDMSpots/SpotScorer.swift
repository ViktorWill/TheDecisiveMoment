import Foundation
import TDMCore

/// What a candidate brings to the scorer, `docs/SPOTFORGE.md` §8.
///
/// Ranking lives here rather than in the pipeline so that changing the weights
/// does not require rebuilding a bundle — but that only works if the raw
/// signals travel with the spot, which is what this carries.
public struct SpotScoringInput: Sendable, Hashable {
    public var spot: Spot
    /// Geotagged Commons photos in the spot's cell and its eight neighbours.
    public var photoCount: Int
    /// Radius the count describes, for the detail sentence.
    public var photoRadiusMetres: Double
    /// Wikipedia language editions with an article. Crude, robust, and far
    /// better than nothing. `nil` when the spot is not in Wikidata.
    public var sitelinks: Int?
    /// Added before normalisation, from `score_boost` in the curated YAML.
    public var curationBoost: Double
    /// Which curated list this came from, e.g. "NYC canon".
    public var curationNote: String?

    public init(
        spot: Spot,
        photoCount: Int = 0,
        photoRadiusMetres: Double = 150,
        sitelinks: Int? = nil,
        curationBoost: Double = 0,
        curationNote: String? = nil
    ) {
        self.spot = spot
        self.photoCount = photoCount
        self.photoRadiusMetres = photoRadiusMetres
        self.sitelinks = sitelinks
        self.curationBoost = curationBoost
        self.curationNote = curationNote
    }
}

/// The city-wide scoring pass.
///
/// Scores are normalised *within* a city, so a Berlin 0.8 and a Tokyo 0.8 mean
/// the same thing relative to their own city — an absolute scale would just
/// report which city is more photographed.
public enum SpotScorer {
    public static let photoDensityWeight = 0.45
    public static let notabilityWeight = 0.25
    public static let featurePriorWeight = 0.20
    public static let curationWeight = 1.00

    /// Sitelink count treated as fully notable. 100 editions is Times Square
    /// territory; everything else lands below it.
    public static let notabilityReference = 100.0

    /// Fixed table by `kind`. `landmark` scores low on purpose: a monument with
    /// 4000 photos of the monument is not a street photography spot, the photo
    /// density term has already over-rewarded it, and this pulls it back.
    public static func featurePrior(for kind: SpotKind) -> Double {
        switch kind {
        case .market: 0.9
        case .plaza: 0.85
        case .transit: 0.8
        case .street: 0.8
        case .stairs: 0.7
        case .underpass: 0.7
        case .intersection: 0.7
        case .bridge: 0.65
        case .waterfront: 0.6
        case .arcade: 0.6
        case .viewpoint: 0.5
        case .park: 0.45
        case .landmark: 0.4
        case .other: 0.2
        }
    }

    /// Score a whole city at once. The normalisation is city-wide, so there is
    /// deliberately no single-spot entry point.
    public static func score(_ inputs: [SpotScoringInput]) -> [Spot] {
        guard !inputs.isEmpty else { return [] }

        let reference = photoCountPercentile95(inputs.map(\.photoCount))
        let terms = inputs.map { weightedTerms(for: $0, photoCountReference: reference) }
        let maximumRaw = terms.map { $0.map(\.contribution).reduce(0, +) }.max() ?? 0

        return zip(inputs, terms).map { input, rawFactors in
            var spot = input.spot
            // Dividing by the city maximum makes the top spot 1.0 and keeps the
            // factors' shares intact, so `scoreFactors` still sums to `score`
            // and the UI can show the breakdown without it contradicting the
            // number.
            let scale = maximumRaw > 0 ? 1 / maximumRaw : 0
            let factors = rawFactors.map {
                ScoreFactor(kind: $0.kind, contribution: round6($0.contribution * scale), detail: $0.detail)
            }
            let (score, reconciled) = reconcile(factors)
            spot.scoreFactors = reconciled
            spot.score = score
            return spot
        }
    }

    /// Rounding each factor independently can leave the published breakdown a
    /// microscopic amount away from the published score, and clamping can move
    /// the score further still. The residual is folded into the largest factor
    /// so `scoreFactors` always sums to `score` exactly.
    private static func reconcile(_ factors: [ScoreFactor]) -> (score: Double, factors: [ScoreFactor]) {
        let total = round6(factors.map(\.contribution).reduce(0, +))
        let score = round6(min(1, max(0, total)))
        guard score != total, let index = largestContributionIndex(in: factors) else {
            return (score, factors)
        }
        var adjusted = factors
        adjusted[index].contribution = round6(adjusted[index].contribution + (score - total))
        return (score, adjusted)
    }

    private static func largestContributionIndex(in factors: [ScoreFactor]) -> Int? {
        factors.indices.max { factors[$0].contribution < factors[$1].contribution }
    }

    /// The 95th percentile by nearest rank: sort ascending, take element
    /// `ceil(0.95 · n) - 1`. The percentile rather than the maximum so one
    /// hyper-photographed landmark does not flatten everything else.
    public static func photoCountPercentile95(_ counts: [Int]) -> Int {
        let sorted = counts.sorted()
        guard let last = sorted.last else { return 0 }
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up))
        guard rank >= 1 else { return last }
        return sorted[min(rank, sorted.count) - 1]
    }

    /// `log1p(count) / log1p(p95)`, clamped. Log because photo counts are
    /// wildly heavy-tailed — a linear term would make every spot in a city zero
    /// except the cathedral.
    static func photoDensityNorm(count: Int, reference: Int) -> Double {
        guard count > 0, reference > 0 else { return 0 }
        let denominator = log1p(Double(reference))
        guard denominator > 0 else { return 0 }
        return min(1, log1p(Double(count)) / denominator)
    }

    static func notabilityNorm(sitelinks: Int?) -> Double {
        guard let sitelinks, sitelinks > 0 else { return 0 }
        return min(1, log1p(Double(sitelinks)) / log1p(notabilityReference))
    }

    /// The weighted terms before city normalisation. Every term emits a factor,
    /// including the ones worth nothing, so the reason a spot ranks low is as
    /// legible as the reason another ranks high.
    static func weightedTerms(for input: SpotScoringInput, photoCountReference: Int) -> [ScoreFactor] {
        var factors: [ScoreFactor] = []

        let density = photoDensityNorm(count: input.photoCount, reference: photoCountReference)
        factors.append(
            ScoreFactor(
                kind: .photoDensity,
                contribution: photoDensityWeight * density,
                detail: photoDensityDetail(for: input)
            )
        )

        let notability = notabilityNorm(sitelinks: input.sitelinks)
        let notabilityDetail: String
        if let sitelinks = input.sitelinks, sitelinks > 0 {
            if let qid = input.spot.refs["wikidata"] {
                notabilityDetail = "Wikidata: \(qid), \(sitelinks) language editions"
            } else {
                notabilityDetail = "\(sitelinks) Wikipedia language editions"
            }
        } else {
            notabilityDetail = "not in Wikidata"
        }
        factors.append(ScoreFactor(kind: .notability, contribution: notabilityWeight * notability, detail: notabilityDetail))

        factors.append(
            ScoreFactor(
                kind: .featurePrior,
                contribution: featurePriorWeight * featurePrior(for: input.spot.kind),
                detail: input.spot.kind.rawValue
            )
        )

        let boost = input.curationBoost.isFinite ? min(1, max(0, input.curationBoost)) : 0
        if input.spot.curated || boost > 0 {
            factors.append(
                ScoreFactor(
                    kind: .curation,
                    contribution: curationWeight * boost,
                    detail: input.curationNote.map { "curated: \($0)" } ?? "curated"
                )
            )
        }

        return factors
    }

    /// The radius arrives from the pipeline as metres. A non-finite or absurd
    /// one would trap on conversion to `Int`, and a detail string is not worth
    /// crashing an import over, so it is dropped from the sentence instead.
    private static func photoDensityDetail(for input: SpotScoringInput) -> String {
        guard input.photoCount > 0 else { return "no geotagged photos nearby" }
        let metres = input.photoRadiusMetres.rounded()
        guard metres.isFinite, metres > 0, metres < Double(Int.max) else {
            return "\(input.photoCount) geotagged photos nearby"
        }
        return "\(input.photoCount) geotagged photos within \(Int(metres)) m"
    }

    /// Six decimals: enough to be exact for a `0…1` score, few enough that a
    /// regenerated bundle does not diff on floating-point noise.
    private static func round6(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
