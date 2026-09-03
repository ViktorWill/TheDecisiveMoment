import Foundation
import TDMCore

/// How far a candidate may sit from the aim before it is a discard, §7a.
///
/// Two things are going on and they pull in opposite directions. The **medium**
/// says what survives: three stops over is a usable black-and-white negative,
/// half a stop over is a ruined slide. The **ladder** says how precisely the aim
/// can be hit at all: whole aperture stops and a doubling shutter dial cannot do
/// better than about a third of a stop, and offering a setting further out than
/// that when a closer one exists is noise rather than choice.
///
/// So the tolerance is the tighter of the two, taken separately on each side of
/// the aim. On negative film and on digital the ladder binds and the band works
/// out at the familiar ±1/3 around the meter; on slide the medium's over side
/// binds first and the band closes up on the highlights. The bias moves the aim,
/// not the width: see ``ExposureSolver`` for where `EV_target = EV_scene − bias`
/// is applied.
public struct ExposureTolerance: Sendable, Equatable {
    /// The medium's own limits, before the ladder is taken into account.
    public let latitude: Latitude
    /// Where the solver aims, in stops away from the meter reading.
    public let biasEV: Double
    /// How much more light than the aim a candidate may give.
    public let overStops: Double
    /// How much less.
    public let underStops: Double

    public init(medium: Medium, precisionEV: Double) {
        latitude = medium.latitude
        biasEV = medium.biasEV
        overStops = min(latitude.overStops, precisionEV - biasEV)
        underStops = min(latitude.underStops, precisionEV + biasEV)
    }

    /// - Parameter aimErrorEV: Signed error against `EV_target`. Negative is
    ///   more light than the aim, positive is less.
    public func accepts(aimErrorEV: Double) -> Bool {
        aimErrorEV <= underStops + 1e-9 && -aimErrorEV <= overStops + 1e-9
    }
}

/// An aperture the body cannot expose, whatever the dial says.
///
/// f/2 in bright sun on ISO 400 wants 1/35 120 s. The M6 stops at 1/1000 and the
/// M10 at 1/4000, so the honest answer is an ND filter or a slower roll — not a
/// quiet substitution of f/5.6, which answers a question nobody asked, §7b.
public struct UnreachableAperture: Sendable, Equatable {
    public let aperture: Double
    public let iso: Int
    /// What the exposure actually needs, seconds.
    public let requiredShutter: TimeInterval
    /// The fastest speed the body has, seconds.
    public let fastestShutter: TimeInterval
    /// How much light has to be taken away to bring it onto the dial, stops.
    public let neutralDensityStops: Double

    public init(
        aperture: Double,
        iso: Int,
        requiredShutter: TimeInterval,
        fastestShutter: TimeInterval,
        neutralDensityStops: Double
    ) {
        self.aperture = aperture
        self.iso = iso
        self.requiredShutter = requiredShutter
        self.fastestShutter = fastestShutter
        self.neutralDensityStops = neutralDensityStops
    }
}

/// Something the photographer can actually do about a scene the gear cannot
/// expose, in the order §7b gives them.
public enum ExposureLever: Sendable, Equatable {
    /// Push or pull the roll. Free, decided in development, costs grain.
    case rate(roll: LoadedRoll, setting: ExposureRecommendation?)
    /// Accept a slower shutter than the handheld floor, and some blur.
    case lowerFloor(shutter: TimeInterval, setting: ExposureRecommendation?)
    /// Take light away, which is the bright-sun case.
    case neutralDensity(stops: Int)
    /// The honest answer when the gap is more than two stops.
    case differentRoll(isoSpeed: Int)
    /// Digital: the ceiling, not the sensor, is what is in the way, §7d.
    case raiseCeiling(toISO: Int)
}

/// Why there is no setting, and what to do instead.
///
/// This is a first-class answer rather than an empty list: on a fixed roll,
/// *"HP5 400 is 0.9 stops short here"* is the most useful thing the app can say.
public struct ExposureShortfall: Sendable, Equatable {
    /// Which way the light is missing.
    public enum Sense: Sendable, Equatable {
        /// The scene is darker than the roll can hold.
        case needsMoreLight
        /// Too much light for the roll and the dial — the ND case.
        case needsLessLight
    }

    /// How far the nearest settable candidate is from the **meter reading**, in
    /// stops. This is the number the screen states.
    public let stops: Double
    /// The same gap measured against the medium's aim, which is what a push has
    /// to close, since push comes in whole stops.
    public let aimStops: Double
    public let sense: Sense
    /// The nearest thing to a setting, for context. Not a recommendation.
    public let closest: ExposureRecommendation?
    /// What would work, best first.
    public let levers: [ExposureLever]
    /// The failure in the terms the older throwing API reports.
    public let reason: ExposureSolverError

    public init(
        stops: Double,
        aimStops: Double,
        sense: Sense,
        closest: ExposureRecommendation?,
        levers: [ExposureLever],
        reason: ExposureSolverError
    ) {
        self.stops = stops
        self.aimStops = aimStops
        self.sense = sense
        self.closest = closest
        self.levers = levers
        self.reason = reason
    }

    /// §7b: under two stops the roll is salvageable; past two, this is the wrong
    /// film for this light, and that is worth knowing before the frame is burnt.
    public var isSalvageable: Bool { stops <= 2.0 + 1e-9 }
}

/// What the solver has to say: a setting, or the reason there is not one.
public enum ExposureOutcome: Sendable, Equatable {
    case solved(ExposureSolution)
    case noSolution(ExposureShortfall)

    public var solution: ExposureSolution? {
        if case let .solved(solution) = self { return solution }
        return nil
    }

    public var shortfall: ExposureShortfall? {
        if case let .noSolution(shortfall) = self { return shortfall }
        return nil
    }

    /// Every setting worth offering, primary first. Empty only when there is
    /// none — and then ``shortfall`` says why.
    public var recommendations: [ExposureRecommendation] {
        guard let solution else { return [] }
        return [solution.primary] + solution.alternatives
    }
}

/// A solved ISO on a digital body, §7d.
public struct ISORecommendation: Sendable, Equatable {
    /// What the exposure needs exactly — 1562 for f/2 · 1/125 at EV100 5.0.
    public let exact: Double
    /// The body's next real step at or above ``exact``. Never below: down means
    /// under-exposure, which is the direction with the least shadow latitude and
    /// the one people reach for by habit.
    public let iso: Int
    /// Whether ``exact`` is above the user's ceiling, in which case the app says
    /// it is short rather than exceeding it.
    public let exceedsCeiling: Bool

    public init(exact: Double, iso: Int, exceedsCeiling: Bool) {
        self.exact = exact
        self.iso = iso
        self.exceedsCeiling = exceedsCeiling
    }

    /// Stops above the ceiling, when it is exceeded.
    public var stopsAboveCeiling: Double {
        exceedsCeiling ? log2(exact / Double(iso)) : 0
    }
}
