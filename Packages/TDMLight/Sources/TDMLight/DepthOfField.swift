import Foundation

/// The sharp range around a focus distance, `docs/EXPOSURE-MODEL.md` §6.
///
/// Distances are metres at this boundary; the maths runs in millimetres inside.
public struct FocusRange: Sendable, Equatable {
    /// Nearest sharp distance, metres.
    public let nearMetres: Double
    /// Farthest sharp distance, metres; `.infinity` when focus is at or beyond
    /// the hyperfocal distance.
    public let farMetres: Double
    /// The distance actually focused on, metres. An engraved mark when the range
    /// came from a lens's barrel.
    public let focusMetres: Double
    /// Hyperfocal distance for the focal length, aperture and circle of
    /// confusion used, metres.
    public let hyperfocalMetres: Double

    public init(nearMetres: Double, farMetres: Double, focusMetres: Double, hyperfocalMetres: Double) {
        self.nearMetres = nearMetres
        self.farMetres = farMetres
        self.focusMetres = focusMetres
        self.hyperfocalMetres = hyperfocalMetres
    }

    /// True when the far limit runs to infinity.
    public var reachesInfinity: Bool { farMetres.isInfinite }

    /// Depth of the sharp zone in metres, `.infinity` when it reaches infinity.
    public var depthMetres: Double { farMetres - nearMetres }

    /// True when the whole of `range` is sharp.
    public func covers(_ range: ClosedRange<Double>) -> Bool {
        nearMetres <= range.lowerBound && farMetres >= range.upperBound
    }
}

/// Depth-of-field and zone-focus maths, `docs/EXPOSURE-MODEL.md` §6.
public enum DepthOfField {
    /// Full-frame circle of confusion, millimetres. 0.025 mm is the stricter
    /// standard; both are offered per gear profile.
    public static let fullFrameCircleOfConfusionMillimetres = 0.030

    /// Hyperfocal distance in metres.
    ///
    /// `H = f² / (N · c) + f`, with `f` and `c` in millimetres — the classic
    /// form including the `+ f` term, which matters at short focus distances.
    public static func hyperfocalMetres(
        focalLengthMillimetres f: Double,
        aperture N: Double,
        circleOfConfusionMillimetres c: Double = fullFrameCircleOfConfusionMillimetres
    ) -> Double {
        hyperfocalMillimetres(focalLengthMillimetres: f, aperture: N, circleOfConfusionMillimetres: c) / 1000
    }

    static func hyperfocalMillimetres(
        focalLengthMillimetres f: Double,
        aperture N: Double,
        circleOfConfusionMillimetres c: Double
    ) -> Double {
        (f * f) / (N * c) + f
    }

    /// The sharp range for a focus distance, in metres.
    ///
    /// `Dn = s(H − f) / (H + s − 2f)`, `Df = s(H − f) / (H − s)` and `∞` when
    /// `s ≥ H`. Everything is converted to millimetres first so the `f` terms
    /// stay in the same units as `H`.
    public static func range(
        focalLengthMillimetres f: Double,
        aperture N: Double,
        focusDistanceMetres s: Double,
        circleOfConfusionMillimetres c: Double = fullFrameCircleOfConfusionMillimetres
    ) -> FocusRange {
        let H = hyperfocalMillimetres(
            focalLengthMillimetres: f,
            aperture: N,
            circleOfConfusionMillimetres: c
        )
        guard s.isFinite else {
            // Focused at infinity: sharp from the hyperfocal distance outwards.
            return FocusRange(
                nearMetres: H / 1000,
                farMetres: .infinity,
                focusMetres: .infinity,
                hyperfocalMetres: H / 1000
            )
        }
        let sMillimetres = s * 1000
        let near = sMillimetres * (H - f) / (H + sMillimetres - 2 * f)
        let far = sMillimetres >= H ? Double.infinity : sMillimetres * (H - f) / (H - sMillimetres)
        return FocusRange(
            nearMetres: near / 1000,
            farMetres: far.isInfinite ? .infinity : far / 1000,
            focusMetres: s,
            hyperfocalMetres: H / 1000
        )
    }
}
