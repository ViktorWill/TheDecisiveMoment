import Foundation

/// The two sentences the app uses about where the sun is.
///
/// Shared by the Light tab's sun panel and the Map's *light right now* strip:
/// the same street, told the same way, on both screens.
enum SolarPhrasing {
    /// `NE` and the seven others. Degrees clockwise from north.
    static func compassPoint(_ azimuthDegrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((azimuthDegrees / 45).rounded()).truncatingRemainder(dividingBy: 8))
        return points[(index + 8) % 8]
    }

    /// One decimal, with a proper minus sign for an elevation below the horizon.
    static func degrees(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }

    /// How near the street axis the sun has to be before neither façade is
    /// front-lit and both are raked instead.
    static let alongStreetDegrees = 20.0

    /// Which façade is lit, from the street's bearing and the sun's azimuth.
    ///
    /// Both are degrees clockwise from north. The lit façade is the one on the
    /// far side of the street from the sun, so it *faces* the sun: its normal is
    /// the street bearing turned 90° towards the sun's side. Naming that
    /// direction — rather than guessing "east" — is the only version of this
    /// sentence that is true for a street of any orientation.
    ///
    /// `nil` when there is no bearing to reason from, or no sun.
    static func litFacade(
        streetBearingDegrees: Double?,
        sunAzimuthDegrees: Double,
        sunElevationDegrees: Double
    ) -> String? {
        guard let streetBearingDegrees, sunElevationDegrees > 0 else { return nil }
        let difference = ((sunAzimuthDegrees - streetBearingDegrees) + 360)
            .truncatingRemainder(dividingBy: 360)
        if difference < alongStreetDegrees
            || difference > 360 - alongStreetDegrees
            || abs(difference - 180) < alongStreetDegrees {
            return nil
        }
        let normal = difference < 180 ? streetBearingDegrees + 90 : streetBearingDegrees - 90
        return compassPoint((normal + 360).truncatingRemainder(dividingBy: 360))
    }

    /// The sun panel's full sentence.
    static func litSideSentence(
        streetBearingDegrees: Double?,
        sunAzimuthDegrees: Double,
        sunElevationDegrees: Double
    ) -> String? {
        guard streetBearingDegrees != nil, sunElevationDegrees > 0 else { return nil }
        guard let facing = litFacade(
            streetBearingDegrees: streetBearingDegrees,
            sunAzimuthDegrees: sunAzimuthDegrees,
            sunElevationDegrees: sunElevationDegrees
        ) else {
            return "Sun along the street — both façades are edge-lit"
        }
        return "Light on the \(facing)-facing façade — shoot with the sun behind you"
    }
}
