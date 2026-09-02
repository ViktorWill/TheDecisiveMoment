import Foundation

/// Everything the light model needs beyond the sun's position.
public struct LightConditions: Sendable, Equatable {
    /// Apparent solar elevation, degrees.
    public var sunElevationDegrees: Double
    /// WeatherKit `cloudCover` in `0…1`, or `nil` when there is no weather and
    /// the model must fall back to clear sky.
    public var cloudCover: Double?
    /// How current the weather is; drives σ, not the EV itself.
    public var weatherFreshness: WeatherFreshness
    public var precipitation: Precipitation
    public var scene: ScenePreset
    public var subjectLighting: SubjectLighting
    /// The preset to blend into through twilight and to use outright at night.
    public var nightPreset: NightPreset
    /// The user's stored offset for this `(scene, daylight|artificial)` pair,
    /// learned from the live meter. §4d; applied last.
    public var calibrationOffsetEV: Double

    public init(
        sunElevationDegrees: Double,
        cloudCover: Double? = nil,
        weatherFreshness: WeatherFreshness = .fresh,
        precipitation: Precipitation = .none,
        scene: ScenePreset = .openSky,
        subjectLighting: SubjectLighting = .frontLit,
        nightPreset: NightPreset = .litCommercialStreet,
        calibrationOffsetEV: Double = 0
    ) {
        self.sunElevationDegrees = sunElevationDegrees
        self.cloudCover = cloudCover
        self.weatherFreshness = weatherFreshness
        self.precipitation = precipitation
        self.scene = scene
        self.subjectLighting = subjectLighting
        self.nightPreset = nightPreset
        self.calibrationOffsetEV = calibrationOffsetEV
    }
}

/// An EV100 estimate with the working shown, so the UI can explain itself.
public struct LightEstimate: Sendable, Equatable {
    /// The answer: EV100 after every modifier.
    public let ev100: Double
    /// Stated uncertainty, §9. Present as `EV100 ± σ`.
    public let sigmaEV: Double
    public let regime: LightRegime
    /// Clear-sky horizontal EV100 before any modifier, §2–§3.
    public let ambientHorizontalEV100: Double
    /// Fraction of the night preset mixed in, `0` in daylight, `1` below −6°.
    public let nightBlendFraction: Double
    public let subjectDeltaEV: Double
    public let cloudDeltaEV: Double
    public let precipitationDeltaEV: Double
    public let sceneDeltaEV: Double
    public let calibrationDeltaEV: Double
    /// True when the subject is back-lit: the model does not predict a
    /// silhouette and the app should say so instead of showing a number.
    public let warnsAboutSilhouette: Bool
    /// True when the estimate used the clear-sky fallback for want of weather.
    public let usedClearSkyFallback: Bool

    public init(
        ev100: Double,
        sigmaEV: Double,
        regime: LightRegime,
        ambientHorizontalEV100: Double,
        nightBlendFraction: Double,
        subjectDeltaEV: Double,
        cloudDeltaEV: Double,
        precipitationDeltaEV: Double,
        sceneDeltaEV: Double,
        calibrationDeltaEV: Double,
        warnsAboutSilhouette: Bool,
        usedClearSkyFallback: Bool
    ) {
        self.ev100 = ev100
        self.sigmaEV = sigmaEV
        self.regime = regime
        self.ambientHorizontalEV100 = ambientHorizontalEV100
        self.nightBlendFraction = nightBlendFraction
        self.subjectDeltaEV = subjectDeltaEV
        self.cloudDeltaEV = cloudDeltaEV
        self.precipitationDeltaEV = precipitationDeltaEV
        self.sceneDeltaEV = sceneDeltaEV
        self.calibrationDeltaEV = calibrationDeltaEV
        self.warnsAboutSilhouette = warnsAboutSilhouette
        self.usedClearSkyFallback = usedClearSkyFallback
    }

    public var ev100Range: ClosedRange<Double> { (ev100 - sigmaEV)...(ev100 + sigmaEV) }
}

/// The ambient light model of `docs/EXPOSURE-MODEL.md` §2–§5, composed.
public enum LightModel {
    /// EV100 for a set of conditions, with the per-term breakdown and σ.
    ///
    /// Modifiers are additive in stops and applied in the order of the document:
    /// subject geometry (4a), cloud (4b), scene (4c), calibration last (4d).
    /// Below the horizon the daylight total is blended linearly into the night
    /// preset, reaching it at −6° (§5).
    public static func estimate(_ conditions: LightConditions) -> LightEstimate {
        let h = conditions.sunElevationDegrees
        let usedFallback = conditions.cloudCover == nil
        let cover = conditions.cloudCover ?? 0

        let ambient = Illuminance.clearSkyHorizontalEV100(sunElevationDegrees: h)
        let subject = Modifiers.subjectDeltaEV(
            sunElevationDegrees: h,
            lighting: conditions.subjectLighting
        )
        let cloud = Modifiers.cloudDeltaEV(cover: cover)
        let precipitation = conditions.precipitation.deltaEV
        let scene = conditions.scene.deltaEV
        let daylightTotal = ambient + subject + cloud + precipitation + scene

        // §5: between 0° and −6° blend linearly between the daylight value and
        // the selected night preset; below −6° the daylight model is abandoned.
        let blend = NightPreset.blendFraction(sunElevationDegrees: h)
        let blended = daylightTotal * (1 - blend) + conditions.nightPreset.ev100 * blend

        let regime = NightPreset.regime(sunElevationDegrees: h)
        // No cloud cover means the clear-sky fallback, whatever the caller said
        // about freshness; §9 widens σ for exactly that case.
        let weather: WeatherFreshness = usedFallback ? .unavailable : conditions.weatherFreshness
        let sigma = Uncertainty.sigmaEV(
            sunElevationDegrees: h,
            regime: regime,
            weather: weather
        )

        return LightEstimate(
            ev100: blended + conditions.calibrationOffsetEV,
            sigmaEV: sigma,
            regime: regime,
            ambientHorizontalEV100: ambient,
            nightBlendFraction: blend,
            subjectDeltaEV: subject,
            cloudDeltaEV: cloud,
            precipitationDeltaEV: precipitation,
            sceneDeltaEV: scene,
            calibrationDeltaEV: conditions.calibrationOffsetEV,
            warnsAboutSilhouette: conditions.subjectLighting.warnsAboutSilhouette,
            usedClearSkyFallback: usedFallback
        )
    }
}
