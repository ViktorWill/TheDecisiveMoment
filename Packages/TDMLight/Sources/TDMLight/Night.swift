import Foundation

/// Night and artificial-light presets, `docs/EXPOSURE-MODEL.md` §5.
///
/// Below `h = −6°` the daylight model does not apply and must not be
/// extrapolated, so this is a lookup rather than a derivation. The UI should
/// present it as an estimate to be checked against the live meter.
public enum NightPreset: String, Sendable, CaseIterable, Codable {
    /// Bright neon, Times Square, illuminated shopfronts. EV100 8–9.
    case brightNeon
    /// Well-lit commercial street. EV100 6–7.
    case litCommercialStreet
    /// Ordinary residential street. EV100 4–5.
    case residentialStreet
    /// Dim side street or park path. EV100 2–3.
    case dimSideStreet

    /// The published EV100 range for the preset.
    public var ev100Range: ClosedRange<Double> {
        switch self {
        case .brightNeon: 8...9
        case .litCommercialStreet: 6...7
        case .residentialStreet: 4...5
        case .dimSideStreet: 2...3
        }
    }

    /// The single EV100 the model uses: the midpoint of the published range.
    public var ev100: Double {
        (ev100Range.lowerBound + ev100Range.upperBound) / 2
    }
}

/// Which part of the model produced a number, `docs/EXPOSURE-MODEL.md` §5 and §9.
public enum LightRegime: String, Sendable, CaseIterable {
    /// Sun above the horizon: the derived daylight model.
    case daylight
    /// Sun between 0° and −6°: a linear blend into the night preset.
    case twilight
    /// Sun below −6°: the night preset alone.
    case night
}

extension NightPreset {
    /// Elevation, degrees, at which the blend is fully the night preset.
    public static let blendFloorElevationDegrees = -6.0

    /// Fraction of the night preset in the twilight blend, `0` at `h = 0°` and
    /// `1` at `h = −6°`.
    static func blendFraction(sunElevationDegrees h: Double) -> Double {
        if h >= 0 { return 0 }
        if h <= blendFloorElevationDegrees { return 1 }
        return h / blendFloorElevationDegrees
    }

    /// The regime a sun elevation falls in.
    public static func regime(sunElevationDegrees h: Double) -> LightRegime {
        if h >= 0 { return .daylight }
        if h > blendFloorElevationDegrees { return .twilight }
        return .night
    }
}
