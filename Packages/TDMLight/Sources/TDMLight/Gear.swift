import Foundation
import TDMCore

/// The ISO a body can actually deliver.
///
/// Film mode is a real constraint, not a nicety: the roll speed is fixed for the
/// whole roll, so the solver has two degrees of freedom instead of three and can
/// legitimately find none. On a sensor the ISO is the third variable, bounded by
/// a ceiling the user sets, `docs/EXPOSURE-MODEL.md` §7b–7d.
public enum ISOAvailability: Sendable, Equatable {
    /// A loaded roll, at the speed it is rated at.
    case fixed(LoadedRoll)
    /// A sensor's usable range, enumerated in full stops from `minimum`, with
    /// the ceiling past which the user does not want the file.
    case range(minimum: Int, maximum: Int, ceiling: Int)

    /// A roll whose stock the photographer has not named — just a speed.
    public static func fixed(_ speed: Int) -> ISOAvailability {
        .fixed(LoadedRoll(speed: speed))
    }

    /// A sensor with no ceiling set: nothing on the body is ruled out.
    public static func range(minimum: Int, maximum: Int) -> ISOAvailability {
        .range(minimum: minimum, maximum: maximum, ceiling: maximum)
    }

    /// Every ISO the body offers, ceiling ignored.
    public var availableValues: [Int] {
        switch self {
        case let .fixed(roll):
            return roll.ratedAt > 0 ? [roll.ratedAt] : []
        case let .range(minimum, maximum, _):
            guard minimum > 0, maximum >= minimum else { return [] }
            var values: [Int] = []
            var value = Double(minimum)
            while Int(value.rounded()) <= maximum {
                values.append(Int(value.rounded()))
                value *= 2
            }
            if values.isEmpty { values = [minimum] }
            return values
        }
    }

    /// The ISO values the solver may choose from: the ladder, capped at the
    /// ceiling. The solver says it is short rather than exceeding it, §7d.
    public var solvableValues: [Int] {
        guard let ceiling else { return availableValues }
        return availableValues.filter { $0 <= ceiling }
    }

    public var ceiling: Int? {
        if case let .range(_, _, ceiling) = self { return ceiling }
        return nil
    }

    /// What the light lands on, which sets tolerance and bias, §7a.
    public var medium: Medium {
        switch self {
        case let .fixed(roll): roll.medium
        case .range: .digital
        }
    }

    public var loadedRoll: LoadedRoll? {
        if case let .fixed(roll) = self { return roll }
        return nil
    }

    /// Whether the ISO is a fact of the loaded roll rather than a variable.
    public var isFixed: Bool { loadedRoll != nil }
}

/// A body, as far as the exposure solver is concerned.
///
/// `TDMCore` gains the richer `CameraBody` value type in M2; this is the subset
/// the maths needs, so `TDMLight` stays free of anything it does not use.
public struct CameraBodyProfile: Sendable, Equatable {
    public var name: String
    /// The body's real shutter ladder, in seconds. `1/250`, never `250`.
    public var shutterSpeeds: [TimeInterval]
    public var iso: ISOAvailability
    /// Circle of confusion for the format, millimetres. 0.030 mm for full frame.
    public var circleOfConfusionMillimetres: Double

    public init(
        name: String,
        shutterSpeeds: [TimeInterval],
        iso: ISOAvailability,
        circleOfConfusionMillimetres: Double = DepthOfField.fullFrameCircleOfConfusionMillimetres
    ) {
        self.name = name
        self.shutterSpeeds = shutterSpeeds
        self.iso = iso
        self.circleOfConfusionMillimetres = circleOfConfusionMillimetres
    }

    /// What the light lands on. Everything asymmetric about the solver's
    /// tolerance comes from here, §7a.
    public var medium: Medium { iso.medium }

    /// The loaded roll, `nil` on a sensor.
    public var loadedRoll: LoadedRoll? { iso.loadedRoll }

    /// The fastest speed on the dial, seconds — `1/1000` on an M6.
    public var fastestShutter: TimeInterval? { shutterSpeeds.filter { $0 > 0 }.min() }

    /// The slowest speed the photographer would ever hold, seconds.
    public var slowestShutter: TimeInterval? { shutterSpeeds.filter { $0 > 0 }.max() }
}

/// A lens, as far as the exposure and zone-focus maths are concerned.
public struct LensProfile: Sendable, Equatable {
    public var name: String
    public var focalLengthMillimetres: Double
    /// The lens's real aperture stops, as f-numbers.
    public var apertures: [Double]
    /// The distances engraved on the barrel, metres, ascending. `.infinity` is a
    /// legitimate entry. Never recommend a distance that is not in this list.
    public var distanceMarksMetres: [Double]
    /// Minimum focus, metres.
    public var minimumFocusMetres: Double

    public init(
        name: String,
        focalLengthMillimetres: Double,
        apertures: [Double],
        distanceMarksMetres: [Double],
        minimumFocusMetres: Double
    ) {
        self.name = name
        self.focalLengthMillimetres = focalLengthMillimetres
        self.apertures = apertures
        self.distanceMarksMetres = distanceMarksMetres
        self.minimumFocusMetres = minimumFocusMetres
    }

    /// The engraved marks in ascending order.
    public var sortedDistanceMarks: [Double] { distanceMarksMetres.sorted() }
}
