import Foundation

/// How trustworthy the weather input is, `docs/EXPOSURE-MODEL.md` §9.
public enum WeatherFreshness: String, Sendable, CaseIterable {
    /// A recent observation or forecast for this hour.
    case fresh
    /// Cached longer than the model considers current.
    case stale
    /// No weather at all; the model falls back to clear sky and widens σ.
    case unavailable
}

/// Stated uncertainty on an EV100 estimate, `docs/EXPOSURE-MODEL.md` §9.
///
/// Never present more precision than this supports: "f/8, about 1/250" is
/// honest, a recommendation to 1/10 stop is not.
public enum Uncertainty {
    /// σ in EV for a set of conditions.
    ///
    /// Base term from the regime and the sun's height, then `+0.7 EV` in
    /// quadrature when there is no weather data and the model has fallen back to
    /// clear sky.
    public static func sigmaEV(
        sunElevationDegrees: Double,
        regime: LightRegime,
        weather: WeatherFreshness
    ) -> Double {
        let base: Double
        switch regime {
        case .night:
            base = 1.5
        case .twilight:
            base = 1.2
        case .daylight:
            if sunElevationDegrees > 15, weather == .fresh {
                base = 0.5
            } else {
                base = 0.8
            }
        }
        guard weather == .unavailable else { return base }
        // Independent error sources add in quadrature.
        return (base * base + 0.7 * 0.7).squareRoot()
    }
}
