import Foundation

/// Apparent position of the sun as seen from a point on the ground.
///
/// Angles are degrees, as everywhere at an API boundary in this package.
public struct SolarPosition: Sendable, Equatable {
    /// Apparent (refraction-corrected) elevation above the horizon, degrees.
    public let elevationDegrees: Double
    /// Azimuth, degrees clockwise from true north.
    public let azimuthDegrees: Double
    /// Solar declination, degrees. Exposed because it is the useful sanity check.
    public let declinationDegrees: Double
    /// Equation of time, minutes.
    public let equationOfTimeMinutes: Double

    public init(
        elevationDegrees: Double,
        azimuthDegrees: Double,
        declinationDegrees: Double,
        equationOfTimeMinutes: Double
    ) {
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.declinationDegrees = declinationDegrees
        self.equationOfTimeMinutes = equationOfTimeMinutes
    }
}

/// The NOAA solar position algorithm, `docs/EXPOSURE-MODEL.md` §1.
///
/// Pure maths on a UTC instant and a coordinate: no clock, no location services,
/// no network. Everything here is deterministic and testable on Linux.
public enum Solar {
    /// Apparent solar position for a UTC instant at a coordinate.
    ///
    /// - Parameters:
    ///   - date: The instant, interpreted as UTC.
    ///   - latitudeDegrees: Latitude, degrees north of the equator.
    ///   - longitudeDegrees: Longitude, degrees east of Greenwich.
    public static func position(
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> SolarPosition {
        // NOAA General Solar Position Calculations. All polynomial coefficients
        // are in degrees; `T` is Julian centuries from J2000.0.
        let jd = julianDay(date)
        let T = (jd - 2_451_545.0) / 36_525.0

        // Geometric mean longitude of the sun, degrees, wrapped to 0..<360.
        let L0 = (280.46646 + T * (36_000.76983 + T * 0.0003032)).wrappedDegrees
        // Geometric mean anomaly, degrees.
        let M = 357.52911 + T * (35_999.05029 - 0.0001537 * T)
        let MRad = M * .pi / 180
        // Eccentricity of Earth's orbit, dimensionless.
        let eccentricity = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
        // Equation of centre, degrees.
        let C = sin(MRad) * (1.914602 - T * (0.004817 + 0.000014 * T))
            + sin(2 * MRad) * (0.019993 - 0.000101 * T)
            + sin(3 * MRad) * 0.000289
        let trueLongitude = L0 + C
        // Longitude of the ascending node of the moon's orbit, degrees; drives
        // the nutation terms below.
        let omega = 125.04 - 1934.136 * T
        let omegaRad = omega * .pi / 180
        // Apparent longitude, degrees: true longitude less aberration and nutation.
        let lambda = trueLongitude - 0.00569 - 0.00478 * sin(omegaRad)
        // Mean obliquity of the ecliptic, degrees (arcminute/arcsecond form).
        let epsilon0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
        let epsilon = epsilon0 + 0.00256 * cos(omegaRad)
        let epsilonRad = epsilon * .pi / 180
        let lambdaRad = lambda * .pi / 180
        // Declination, degrees.
        let declination = asin(sin(epsilonRad) * sin(lambdaRad)) * 180 / .pi

        // Equation of time, minutes. `y = tan²(ε/2)`.
        let y = pow(tan(epsilonRad / 2), 2)
        let L0Rad = L0 * .pi / 180
        let equationOfTime = 4 * (180 / .pi) * (
            y * sin(2 * L0Rad)
                - 2 * eccentricity * sin(MRad)
                + 4 * eccentricity * y * sin(MRad) * cos(2 * L0Rad)
                - 0.5 * y * y * sin(4 * L0Rad)
                - 1.25 * eccentricity * eccentricity * sin(2 * MRad)
        )

        // True solar time, minutes past local solar midnight; 4 minutes per
        // degree of longitude.
        let minutesUTC = minutesIntoUTCDay(date)
        let trueSolarTime = (minutesUTC + equationOfTime + 4 * longitudeDegrees)
            .truncatingRemainder(dividingBy: 1440)
        let trueSolarTimeWrapped = trueSolarTime < 0 ? trueSolarTime + 1440 : trueSolarTime
        // Hour angle, degrees; 15° per hour, zero at solar noon.
        var hourAngle = trueSolarTimeWrapped / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let latitudeRad = latitudeDegrees * .pi / 180
        let declinationRad = declination * .pi / 180
        let hourAngleRad = hourAngle * .pi / 180

        let cosZenith = min(
            1.0,
            max(-1.0, sin(latitudeRad) * sin(declinationRad)
                + cos(latitudeRad) * cos(declinationRad) * cos(hourAngleRad))
        )
        let zenithRad = acos(cosZenith)
        let zenithDegrees = zenithRad * 180 / .pi
        let geometricElevation = 90 - zenithDegrees

        // Azimuth from the standard NOAA branch on the sign of the hour angle.
        let azimuthDenominator = cos(latitudeRad) * sin(zenithRad)
        let azimuth: Double
        if abs(azimuthDenominator) > 1e-9 {
            let cosAzimuth = min(
                1.0,
                max(-1.0, (sin(latitudeRad) * cos(zenithRad) - sin(declinationRad)) / azimuthDenominator)
            )
            let angle = acos(cosAzimuth) * 180 / .pi
            azimuth = hourAngle > 0 ? (180 - angle).wrappedDegrees : (180 + angle).wrappedDegrees
        } else {
            // Sun overhead or at a pole: azimuth is undefined; report due south.
            azimuth = 180
        }

        return SolarPosition(
            elevationDegrees: geometricElevation + refractionDegrees(geometricElevationDegrees: geometricElevation),
            azimuthDegrees: azimuth,
            declinationDegrees: declination,
            equationOfTimeMinutes: equationOfTime
        )
    }

    /// Apparent elevation only, in degrees. The hot path for the bisection below.
    public static func elevationDegrees(
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> Double {
        position(date: date, latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees)
            .elevationDegrees
    }

    /// Atmospheric refraction correction, degrees, from the NOAA piecewise fit.
    ///
    /// The published coefficients are arcseconds, hence the `/3600`; the input is
    /// the *geometric* elevation in degrees.
    static func refractionDegrees(geometricElevationDegrees h: Double) -> Double {
        let hRad = h * .pi / 180
        if h > 85 {
            return 0
        } else if h > 5 {
            let t = tan(hRad)
            return (58.1 / t - 0.07 / pow(t, 3) + 0.000086 / pow(t, 5)) / 3600
        } else if h > -0.575 {
            return (1735 + h * (-518.2 + h * (103.4 + h * (-12.79 + h * 0.711)))) / 3600
        } else {
            return (-20.772 / tan(hRad)) / 3600
        }
    }

    /// Julian day from a UTC instant, by the standard Gregorian calendar formula.
    ///
    /// Computed from the Unix epoch so that the package needs no calendar type:
    /// JD 2440587.5 is 1970-01-01T00:00:00Z.
    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Minutes elapsed since the start of the UTC day containing `date`.
    static func minutesIntoUTCDay(_ date: Date) -> Double {
        let seconds = date.timeIntervalSince1970
        let secondsIntoDay = seconds - (seconds / 86_400).rounded(.down) * 86_400
        return secondsIntoDay / 60
    }
}

extension Double {
    /// This value wrapped into `0..<360`.
    var wrappedDegrees: Double {
        let r = truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
