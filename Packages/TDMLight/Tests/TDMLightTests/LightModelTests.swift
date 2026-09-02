import Foundation
import Testing
@testable import TDMLight

@Suite("Ambient illuminance and EV — EXPOSURE-MODEL §2, §3")
struct IlluminanceTests {
    struct Row: Sendable, CustomStringConvertible {
        let elevation: Double
        let lux: Double
        let ev100: Double
        var description: String { "sun \(elevation)°" }
    }

    static let rows: [Row] = [
        Row(elevation: 90, lux: 128_000, ev100: 15.64),
        Row(elevation: 60, lux: 108_485, ev100: 15.41),
        Row(elevation: 45, lux: 85_925, ev100: 15.07),
        Row(elevation: 40, lux: 76_999, ev100: 14.91),
        Row(elevation: 30, lux: 57_680, ev100: 14.49),
        Row(elevation: 20, lux: 37_271, ev100: 13.86),
        Row(elevation: 10, lux: 17_094, ev100: 12.74),
        Row(elevation: 5, lux: 7_737, ev100: 11.60),
        Row(elevation: 0, lux: 700, ev100: 8.13),
        Row(elevation: -3, lux: 49, ev100: 4.30),
        Row(elevation: -6, lux: 3.5, ev100: 0.47),
    ]

    @Test("Every ambient EV row", arguments: rows)
    func row(_ row: Row) {
        let lux = Illuminance.clearSkyHorizontalLux(sunElevationDegrees: row.elevation)
        // The table is rounded to whole lux above 10 lux, so compare relatively.
        #expect(abs(lux - row.lux) <= max(0.5, row.lux * 0.005))
        #expect(abs(Illuminance.ev100(lux: lux) - row.ev100) <= 0.005)
    }

    @Test("Sunny 16 — f/16 at 1/100, ISO 100 is EV100 14.64, not 15")
    func sunny16() {
        let ev = ExposureSolver.exposureValue(aperture: 16, shutter: 1.0 / 100)
        #expect(abs(ev - 14.64) < 0.005)
        #expect(abs(ExposureSolver.measuredEV100(aperture: 16, shutter: 1.0 / 100, iso: 100) - 14.64) < 0.005)
    }

    @Test("Lux and EV100 round-trip")
    func roundTrip() {
        for ev in stride(from: -2.0, through: 16.0, by: 0.5) {
            #expect(abs(Illuminance.ev100(lux: Illuminance.lux(ev100: ev)) - ev) < 1e-9)
        }
    }

    @Test("The twilight branch takes over below 0.5°")
    func twilightBranch() {
        #expect(abs(Illuminance.clearSkyHorizontalLux(sunElevationDegrees: 0) - 700) < 1e-9)
        // ~3.4 lux at the end of civil twilight is the published anchor.
        #expect(abs(Illuminance.clearSkyHorizontalLux(sunElevationDegrees: -6) - 3.4) < 0.2)
    }

    @Test("Other measured-EV sanity rows from the reference script")
    func measuredEVRows() {
        #expect(abs(ExposureSolver.measuredEV100(aperture: 8, shutter: 1.0 / 250, iso: 200) - 12.97) < 0.005)
        #expect(abs(ExposureSolver.measuredEV100(aperture: 5.6, shutter: 1.0 / 125, iso: 400) - 9.94) < 0.005)
        #expect(abs(ExposureSolver.measuredEV100(aperture: 2, shutter: 1.0 / 60, iso: 1600) - 3.91) < 0.005)
    }
}

@Suite("Modifiers — EXPOSURE-MODEL §4")
struct ModifierTests {
    struct SubjectRow: Sendable, CustomStringConvertible {
        let elevation: Double
        let horizontal: Double
        let delta: Double
        let subject: Double
        var description: String { "sun \(elevation)°" }
    }

    static let subjectRows: [SubjectRow] = [
        SubjectRow(elevation: 90, horizontal: 15.64, delta: -1.00, subject: 14.64),
        SubjectRow(elevation: 60, horizontal: 15.41, delta: -0.79, subject: 14.61),
        SubjectRow(elevation: 45, horizontal: 15.07, delta: 0.00, subject: 15.07),
        SubjectRow(elevation: 40, horizontal: 14.91, delta: 0.25, subject: 15.16),
        SubjectRow(elevation: 30, horizontal: 14.49, delta: 0.79, subject: 15.29),
        SubjectRow(elevation: 20, horizontal: 13.86, delta: 1.46, subject: 15.32),
        SubjectRow(elevation: 15, horizontal: 13.40, delta: 1.90, subject: 15.30),
        SubjectRow(elevation: 10, horizontal: 12.74, delta: 2.50, subject: 15.24),
        SubjectRow(elevation: 5, horizontal: 11.60, delta: 3.00, subject: 14.60),
        SubjectRow(elevation: 2, horizontal: 10.08, delta: 3.00, subject: 13.08),
    ]

    @Test("Every vertical-subject row", arguments: subjectRows)
    func subjectRow(_ row: SubjectRow) {
        let horizontal = Illuminance.clearSkyHorizontalEV100(sunElevationDegrees: row.elevation)
        let delta = Modifiers.verticalSubjectDeltaEV(sunElevationDegrees: row.elevation)
        #expect(abs(horizontal - row.horizontal) <= 0.005)
        #expect(abs(delta - row.delta) <= 0.005)
        #expect(abs(horizontal + delta - row.subject) <= 0.005)
    }

    @Test("Sunny 16 holds on a front-lit subject from 5° to 90°")
    func sunny16HoldsAllDay() {
        for elevation in stride(from: 5.0, through: 90.0, by: 1.0) {
            let ev = Illuminance.clearSkyHorizontalEV100(sunElevationDegrees: elevation)
                + Modifiers.verticalSubjectDeltaEV(sunElevationDegrees: elevation)
            #expect(ev >= 14.45 && ev <= 15.35, "sun \(elevation)° gave EV100 \(ev)")
        }
    }

    @Test("Side-lit is half the correction, back-lit and horizontal are none")
    func lightingFractions() {
        let h = 20.0
        let full = Modifiers.verticalSubjectDeltaEV(sunElevationDegrees: h)
        #expect(abs(Modifiers.subjectDeltaEV(sunElevationDegrees: h, lighting: .frontLit) - full) < 1e-12)
        #expect(abs(Modifiers.subjectDeltaEV(sunElevationDegrees: h, lighting: .sideLit) - full / 2) < 1e-12)
        #expect(Modifiers.subjectDeltaEV(sunElevationDegrees: h, lighting: .backLit) == 0)
        #expect(Modifiers.subjectDeltaEV(sunElevationDegrees: h, lighting: .horizontalPlane) == 0)
        #expect(SubjectLighting.backLit.warnsAboutSilhouette)
        #expect(!SubjectLighting.frontLit.warnsAboutSilhouette)
    }

    @Test("The correction is zero below the twilight branch")
    func noCorrectionAtNight() {
        #expect(Modifiers.verticalSubjectDeltaEV(sunElevationDegrees: 0.5) == 0)
        #expect(Modifiers.verticalSubjectDeltaEV(sunElevationDegrees: -3) == 0)
    }

    struct CloudRow: Sendable, CustomStringConvertible {
        let cover: Double
        let delta: Double
        var description: String { "cover \(cover)" }
    }

    static let cloudRows: [CloudRow] = [
        CloudRow(cover: 0.00, delta: 0.00),
        CloudRow(cover: 0.25, delta: -0.28),
        CloudRow(cover: 0.50, delta: -0.92),
        CloudRow(cover: 0.75, delta: -1.84),
        CloudRow(cover: 1.00, delta: -3.00),
    ]

    @Test("Every cloud attenuation row", arguments: cloudRows)
    func cloudRow(_ row: CloudRow) {
        #expect(abs(Modifiers.cloudDeltaEV(cover: row.cover) - row.delta) <= 0.005)
    }

    @Test("Cloud cover is clamped to 0…1")
    func cloudClamping() {
        #expect(Modifiers.cloudDeltaEV(cover: -0.5) == 0)
        #expect(abs(Modifiers.cloudDeltaEV(cover: 1.5) + 3.0) < 1e-12)
    }

    @Test("Scene and precipitation modifiers match the tables")
    func sceneAndPrecipitation() {
        #expect(ScenePreset.openSky.deltaEV == 0.0)
        #expect(ScenePreset.shadedSideOfStreet.deltaEV == -2.5)
        #expect(ScenePreset.narrowCanyon.deltaEV == -3.5)
        #expect(ScenePreset.underArcade.deltaEV == -4.5)
        #expect(ScenePreset.interior.deltaEV == -6.0)
        #expect(Precipitation.none.deltaEV == 0.0)
        #expect(Precipitation.light.deltaEV == -0.5)
        #expect(Precipitation.heavy.deltaEV == -1.0)
    }
}

@Suite("Composed light model — EXPOSURE-MODEL §4, §5, §9")
struct LightModelTests {
    @Test("Worked example: NYC, 21 June 2026, 19:00 EDT, 20% cloud")
    func workedExample() {
        let sunlit = LightModel.estimate(
            LightConditions(
                sunElevationDegrees: 14.727,
                cloudCover: 0.20,
                scene: .openSky,
                subjectLighting: .frontLit
            )
        )
        #expect(abs(sunlit.ambientHorizontalEV100 - 13.37) <= 0.005)
        #expect(abs(sunlit.cloudDeltaEV - (-0.19)) <= 0.005)
        #expect(abs(sunlit.subjectDeltaEV - 1.93) <= 0.005)
        #expect(abs(sunlit.ev100 - 15.10) <= 0.005)

        var shadedConditions = LightConditions(
            sunElevationDegrees: 14.727,
            cloudCover: 0.20,
            subjectLighting: .frontLit
        )
        shadedConditions.scene = .shadedSideOfStreet
        let shaded = LightModel.estimate(shadedConditions)
        #expect(abs(shaded.ev100 - 12.60) <= 0.005)
        // Two and a half stops between the two sides of one street.
        #expect(abs((sunlit.ev100 - shaded.ev100) - 2.5) <= 1e-9)
    }

    @Test("Calibration offset is applied last and shifts the answer one for one")
    func calibrationOffset() {
        var conditions = LightConditions(sunElevationDegrees: 30, cloudCover: 0)
        let base = LightModel.estimate(conditions).ev100
        conditions.calibrationOffsetEV = -0.7
        #expect(abs(LightModel.estimate(conditions).ev100 - (base - 0.7)) < 1e-9)
    }

    @Test("Missing weather falls back to clear sky and widens σ")
    func clearSkyFallback() {
        let withWeather = LightModel.estimate(
            LightConditions(sunElevationDegrees: 30, cloudCover: 0, weatherFreshness: .fresh)
        )
        let without = LightModel.estimate(LightConditions(sunElevationDegrees: 30, cloudCover: nil))
        #expect(without.usedClearSkyFallback)
        #expect(abs(without.ev100 - withWeather.ev100) < 1e-12)
        // Cloud cover is not "known" when there is none, so σ starts at 0.8.
        #expect(abs(without.sigmaEV - (0.8 * 0.8 + 0.7 * 0.7).squareRoot()) < 1e-12)
    }

    @Test("Night presets carry the published EV100 ranges")
    func nightPresets() {
        #expect(NightPreset.brightNeon.ev100Range == 8...9)
        #expect(NightPreset.litCommercialStreet.ev100Range == 6...7)
        #expect(NightPreset.residentialStreet.ev100Range == 4...5)
        #expect(NightPreset.dimSideStreet.ev100Range == 2...3)
        #expect(NightPreset.dimSideStreet.ev100 == 2.5)
    }

    @Test("Below −6° the model is the night preset alone")
    func nightRegime() {
        let estimate = LightModel.estimate(
            LightConditions(
                sunElevationDegrees: -12,
                cloudCover: 0.5,
                scene: .shadedSideOfStreet,
                nightPreset: .brightNeon
            )
        )
        #expect(estimate.regime == .night)
        #expect(estimate.nightBlendFraction == 1)
        #expect(abs(estimate.ev100 - NightPreset.brightNeon.ev100) < 1e-9)
        #expect(estimate.sigmaEV == 1.5)
    }

    @Test("Twilight blends linearly from the daylight value to the preset")
    func twilightBlend() {
        func estimate(at elevation: Double) -> LightEstimate {
            LightModel.estimate(
                LightConditions(
                    sunElevationDegrees: elevation,
                    cloudCover: 0,
                    nightPreset: .residentialStreet
                )
            )
        }
        let horizon = estimate(at: 0)
        #expect(horizon.regime == .daylight)
        #expect(horizon.nightBlendFraction == 0)
        #expect(abs(horizon.ev100 - 8.13) <= 0.005)

        let midway = estimate(at: -3)
        #expect(midway.regime == .twilight)
        #expect(abs(midway.nightBlendFraction - 0.5) < 1e-12)
        let daylightAtMinusThree = Illuminance.clearSkyHorizontalEV100(sunElevationDegrees: -3)
        #expect(abs(midway.ev100 - (daylightAtMinusThree + NightPreset.residentialStreet.ev100) / 2) < 1e-9)
        #expect(midway.sigmaEV == 1.2)

        // The blend is linear in the sun's elevation: three equally spaced
        // elevations give three EV values in arithmetic progression once the
        // daylight term is taken out.
        for elevation in stride(from: -0.5, through: -5.5, by: -0.5) {
            let fraction = estimate(at: elevation).nightBlendFraction
            #expect(abs(fraction - elevation / -6) < 1e-12)
            let daylight = Illuminance.clearSkyHorizontalEV100(sunElevationDegrees: elevation)
            let expected = daylight * (1 - fraction) + NightPreset.residentialStreet.ev100 * fraction
            #expect(abs(estimate(at: elevation).ev100 - expected) < 1e-9)
        }
        #expect(abs(estimate(at: -6).ev100 - NightPreset.residentialStreet.ev100) < 1e-9)
    }

    @Test("Uncertainty table — EXPOSURE-MODEL §9")
    func uncertaintyTable() {
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: 30, regime: .daylight, weather: .fresh) == 0.5)
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: 10, regime: .daylight, weather: .fresh) == 0.8)
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: 30, regime: .daylight, weather: .stale) == 0.8)
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: -3, regime: .twilight, weather: .fresh) == 1.2)
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: -10, regime: .night, weather: .fresh) == 1.5)
        let noWeather = Uncertainty.sigmaEV(sunElevationDegrees: 30, regime: .daylight, weather: .unavailable)
        #expect(abs(noWeather - (0.8 * 0.8 + 0.7 * 0.7).squareRoot()) < 1e-12)
    }

    @Test("The stated range is EV ± σ")
    func statedRange() {
        let estimate = LightModel.estimate(LightConditions(sunElevationDegrees: 40, cloudCover: 0.1))
        #expect(abs(estimate.ev100Range.lowerBound - (estimate.ev100 - estimate.sigmaEV)) < 1e-12)
        #expect(abs(estimate.ev100Range.upperBound - (estimate.ev100 + estimate.sigmaEV)) < 1e-12)
    }
}
