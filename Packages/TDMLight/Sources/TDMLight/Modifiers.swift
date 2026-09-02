import Foundation

/// How the subject stands relative to the light, `docs/EXPOSURE-MODEL.md` §4a.
public enum SubjectLighting: String, Sendable, CaseIterable, Codable {
    /// A vertical subject facing the sun: the full correction applies.
    case frontLit
    /// A vertical subject lit from the side: roughly half the correction.
    case sideLit
    /// A vertical subject with the sun behind it. The correction is zero and the
    /// model does not usefully predict a silhouette — see ``warnsAboutSilhouette``.
    case backLit
    /// Metering the horizontal plane itself (the pavement); no correction.
    case horizontalPlane

    /// Fraction of the vertical-subject correction that applies.
    var correctionFraction: Double {
        switch self {
        case .frontLit: 1.0
        case .sideLit: 0.5
        case .backLit, .horizontalPlane: 0.0
        }
    }

    /// Back-lit street work is a deliberate choice about silhouettes, so the app
    /// should say that rather than pretend the number describes the subject.
    public var warnsAboutSilhouette: Bool { self == .backLit }
}

/// What the sky can actually reach, `docs/EXPOSURE-MODEL.md` §4c.
public enum ScenePreset: String, Sendable, CaseIterable, Codable {
    case openSky
    case shadedSideOfStreet
    case narrowCanyon
    case underArcade
    case interior

    /// Exposure modifier in stops.
    public var deltaEV: Double {
        switch self {
        case .openSky: 0.0
        case .shadedSideOfStreet: -2.5
        case .narrowCanyon: -3.5
        case .underArcade: -4.5
        case .interior: -6.0
        }
    }
}

/// Precipitation intensity, `docs/EXPOSURE-MODEL.md` §4b.
public enum Precipitation: String, Sendable, CaseIterable, Codable {
    case none
    case light
    case heavy

    /// Exposure modifier in stops, added on top of the cloud attenuation.
    public var deltaEV: Double {
        switch self {
        case .none: 0.0
        case .light: -0.5
        case .heavy: -1.0
        }
    }
}

/// The additive stop modifiers of `docs/EXPOSURE-MODEL.md` §4.
///
/// They are applied in the order of the document — subject geometry, cloud,
/// scene, then calibration — because the calibration offset is defined as the
/// last word on everything before it.
public enum Modifiers {
    /// Extra light on a vertical, front-lit subject compared with the horizontal
    /// plane, in stops.
    ///
    /// `ΔEV = clamp(log2(cot h), −1, +3)` for `h > 0.5°`, else 0. A vertical
    /// surface facing a low sun receives far more light than the pavement does,
    /// which is the whole reason golden hour is worth shooting.
    public static func verticalSubjectDeltaEV(sunElevationDegrees h: Double) -> Double {
        guard h > Illuminance.twilightBranchElevationDegrees else { return 0 }
        let cotangent = 1 / tan(h * .pi / 180)
        return min(3.0, max(-1.0, log2(cotangent)))
    }

    /// The vertical-subject correction scaled for how the subject faces the light.
    public static func subjectDeltaEV(
        sunElevationDegrees h: Double,
        lighting: SubjectLighting
    ) -> Double {
        verticalSubjectDeltaEV(sunElevationDegrees: h) * lighting.correctionFraction
    }

    /// Cloud attenuation in stops: `ΔEV = −3.0 · c^1.7` for cover `c` in `0…1`.
    public static func cloudDeltaEV(cover c: Double) -> Double {
        let clamped = min(1.0, max(0.0, c))
        return -3.0 * pow(clamped, 1.7)
    }
}
