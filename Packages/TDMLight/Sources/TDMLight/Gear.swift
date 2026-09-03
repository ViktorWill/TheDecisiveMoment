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

    /// The sensor's own limits, ceiling ignored — what raising the ceiling
    /// could reach. `nil` on film, where there is nothing to raise.
    public var sensorRange: (minimum: Int, maximum: Int)? {
        if case let .range(minimum, maximum, _) = self { return (minimum, maximum) }
        return nil
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

/// Which shutter the body is being asked to use.
///
/// Not a preference: an M11 has 1/16000 only with the electronic shutter
/// switched on, and an M7 has 1/60 and 1/125 and nothing else once the battery
/// is flat. Solving against the wrong ladder is exactly the confident nonsense
/// `docs/SPEC-light.md` warns about.
public enum ShutterMode: String, Sendable, CaseIterable, Equatable {
    /// The dial as it is used: mechanical on a film M, the normal shutter on a
    /// digital one.
    case standard
    /// The electronic shutter, where the body has one.
    case electronic
    /// What is left with a flat battery.
    case flatBattery
}

/// A body, as far as the exposure solver is concerned.
///
/// `TDMCore` gains the richer `CameraBody` value type in M2; this is the subset
/// the maths needs, so `TDMLight` stays free of anything it does not use.
public struct CameraBodyProfile: Sendable, Equatable {
    public var name: String
    /// The body's real shutter ladder, in seconds. `1/250`, never `250`.
    public var mechanicalShutterSpeeds: [TimeInterval]
    /// Speeds the body has only with the electronic shutter on.
    public var electronicShutterSpeeds: [TimeInterval]
    /// Speeds that survive a flat battery — the whole dial on a mechanical M,
    /// 1/60 and 1/125 on an M7, nothing at all on a digital body.
    public var mechanicalFallbackShutterSpeeds: [TimeInterval]
    /// Which of those three ladders the solver is working against.
    public var shutterMode: ShutterMode
    public var iso: ISOAvailability
    /// The frame the body draws. Framing only — it never reaches the exposure
    /// maths, only the depth of field through the circle of confusion below.
    public var format: SensorFormat
    /// Circle of confusion for the format, millimetres. 0.030 mm for full
    /// frame, 0.0225 mm on the M8's APS-H frame.
    public var circleOfConfusionMillimetres: Double
    /// Whether the body meters at all. An M-A does not, and then the phone is
    /// the only meter in the bag, `docs/EXPOSURE-MODEL.md` §8.
    public var hasMeter: Bool
    /// Whether the body will choose the shutter itself. An M7, and nothing else.
    public var supportsAperturePriority: Bool

    public init(
        name: String,
        shutterSpeeds: [TimeInterval],
        electronicShutterSpeeds: [TimeInterval] = [],
        mechanicalFallbackShutterSpeeds: [TimeInterval] = [],
        shutterMode: ShutterMode = .standard,
        iso: ISOAvailability,
        format: SensorFormat = .fullFrame,
        circleOfConfusionMillimetres: Double? = nil,
        hasMeter: Bool = true,
        supportsAperturePriority: Bool = false
    ) {
        self.name = name
        self.mechanicalShutterSpeeds = shutterSpeeds
        self.electronicShutterSpeeds = electronicShutterSpeeds
        self.mechanicalFallbackShutterSpeeds = mechanicalFallbackShutterSpeeds
        self.shutterMode = shutterMode
        self.iso = iso
        self.format = format
        self.circleOfConfusionMillimetres = circleOfConfusionMillimetres
            ?? format.circleOfConfusionMillimetres
        self.hasMeter = hasMeter
        self.supportsAperturePriority = supportsAperturePriority
    }

    /// The speeds actually available in the selected mode, ascending.
    public var shutterSpeeds: [TimeInterval] {
        switch shutterMode {
        case .standard: mechanicalShutterSpeeds.sorted()
        case .electronic: Set(mechanicalShutterSpeeds + electronicShutterSpeeds).sorted()
        case .flatBattery: mechanicalFallbackShutterSpeeds.sorted()
        }
    }

    public var hasElectronicShutter: Bool { !electronicShutterSpeeds.isEmpty }

    /// What the light lands on. Everything asymmetric about the solver's
    /// tolerance comes from here, §7a.
    public var medium: Medium { iso.medium }

    /// The loaded roll, `nil` on a sensor.
    public var loadedRoll: LoadedRoll? { iso.loadedRoll }

    /// The fastest speed in the selected mode, seconds — `1/1000` on an M6.
    public var fastestShutter: TimeInterval? { shutterSpeeds.filter { $0 > 0 }.min() }

    /// The slowest speed the photographer would ever hold, seconds.
    public var slowestShutter: TimeInterval? { shutterSpeeds.filter { $0 > 0 }.max() }

    /// The same body with a different shutter selected.
    public func using(_ mode: ShutterMode) -> CameraBodyProfile {
        var copy = self
        copy.shutterMode = mode
        return copy
    }
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
