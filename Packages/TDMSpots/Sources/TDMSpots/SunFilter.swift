import Foundation
import TDMCore

/// Whether the sun is reaching a spot right now, from its `streetBearing` and
/// `openness` — the *lit now* pill of `docs/SPEC-map.md`.
///
/// The sun's position comes from `TDMLight` and is passed in already computed:
/// it is the same for every spot in a region, so the per-spot work is a handful
/// of arithmetic operations rather than a solar solve. That is what makes the
/// filter that will actually get used cheap enough to run on every region
/// change.
///
/// Angles are degrees clockwise from north, as everywhere at an API boundary.
public struct SunFilter: Sendable, Hashable {
    /// Solar azimuth, degrees clockwise from true north.
    public var azimuthDegrees: Double
    /// Apparent solar elevation, degrees above the horizon.
    public var elevationDegrees: Double

    public init(azimuthDegrees: Double, elevationDegrees: Double) {
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
    }

    /// Below this the sun is not lighting a street in any useful sense, whatever
    /// the geometry — it is behind the buildings of the next block.
    public static let minimumElevationDegrees = 0.0

    /// Above this the sun clears the far wall of an ordinary street canyon
    /// whatever its orientation. A 1:1 height-to-width ratio is the usual
    /// European block, and its shadow line reaches the far kerb at 45°.
    public static let canyonClearanceElevationDegrees = 45.0

    /// How near the street axis the sun has to be for light to run *down* a
    /// canyon rather than be stopped by the wall across it. Manhattanhenge is
    /// the extreme case of this term.
    public static let canyonAlignmentDegrees = 30.0

    /// Whether the sun is above the horizon at all. A `nil`-bearing spot can
    /// still be answered this far, and an unlit sky answers every spot at once.
    public var isDaylight: Bool { elevationDegrees > Self.minimumElevationDegrees }

    /// Whether this spot has sun on it now.
    ///
    /// A spot with no `streetBearing` is treated as unenclosed by the street,
    /// because the alternative — hiding it — would hide most of a generated
    /// bundle for a fact the data does not carry.
    public func isLit(_ spot: Spot) -> Bool {
        isLit(streetBearingDegrees: spot.streetBearing, openness: spot.openness)
    }

    public func isLit(streetBearingDegrees: Double?, openness: Openness) -> Bool {
        guard isDaylight else { return false }
        switch openness {
        // A covered spot — an arcade, an underpass — never has direct sun on it.
        // Saying otherwise is the one answer here that would send someone to the
        // wrong street.
        case .covered:
            return false
        case .open:
            return true
        case .canyon:
            guard let streetBearingDegrees else {
                // Enclosed, but the axis is unknown: the sun has to be high
                // enough to clear the walls whichever way they run.
                return elevationDegrees >= Self.canyonClearanceElevationDegrees
            }
            if elevationDegrees >= Self.canyonClearanceElevationDegrees { return true }
            return Self.axisOffset(
                azimuthDegrees: azimuthDegrees,
                streetBearingDegrees: streetBearingDegrees
            ) <= Self.canyonAlignmentDegrees
        }
    }

    /// The angle between the sun's azimuth and the street axis, folded into
    /// 0…90°: a street is an axis, not a direction, so a bearing of 15° and one
    /// of 195° describe the same street.
    public static func axisOffset(azimuthDegrees: Double, streetBearingDegrees: Double) -> Double {
        let difference = abs(azimuthDegrees - streetBearingDegrees)
            .truncatingRemainder(dividingBy: 180)
        return min(difference, 180 - difference)
    }
}
