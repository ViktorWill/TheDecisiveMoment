import Foundation

/// Ambient illuminance and its conversion to EV100,
/// `docs/EXPOSURE-MODEL.md` §2 and §3.
public enum Illuminance {
    /// Elevation, degrees, below which the daylight branch is abandoned for the
    /// twilight decay.
    public static let twilightBranchElevationDegrees = 0.5

    /// Incident-light meter calibration constant. `EV100 = log2(E · S / C)` with
    /// `S = 100` and `C = 250` collapses to `log2(E / 2.5)`.
    public static let meterCalibrationConstant = 250.0

    /// Clear-sky global horizontal illuminance, lux, for an apparent solar
    /// elevation in degrees.
    ///
    /// `h > 0.5°: E = 128000 · (sin h)^1.15`, the standard clear-sky fit.
    /// `h ≤ 0.5°: E = 700 · e^(0.885 h)`, an exponential anchored on ~700 lux at
    /// the horizon and ~3.4 lux at the end of civil twilight (h = −6°).
    public static func clearSkyHorizontalLux(sunElevationDegrees h: Double) -> Double {
        if h > twilightBranchElevationDegrees {
            return 128_000 * pow(sin(h * .pi / 180), 1.15)
        }
        return 700 * exp(0.885 * h)
    }

    /// EV100 for an illuminance in lux, by the incident-light relation
    /// `EV100 = log2(E · S / C)` with `S = 100`, `C = 250`.
    public static func ev100(lux: Double) -> Double {
        log2(lux * 100 / meterCalibrationConstant)
    }

    /// Illuminance, lux, for an EV100 value. The inverse of ``ev100(lux:)``.
    public static func lux(ev100: Double) -> Double {
        pow(2, ev100) * meterCalibrationConstant / 100
    }

    /// Clear-sky horizontal EV100 for an apparent solar elevation in degrees.
    public static func clearSkyHorizontalEV100(sunElevationDegrees h: Double) -> Double {
        ev100(lux: clearSkyHorizontalLux(sunElevationDegrees: h))
    }
}
