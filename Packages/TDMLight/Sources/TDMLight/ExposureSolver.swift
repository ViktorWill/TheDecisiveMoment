import Foundation
import TDMCore

/// How fast the subject is moving, for the freeze-motion strategy and for
/// manual mode's frozen/not-frozen read on whatever shutter is dialed in.
public enum SubjectMotion: String, Sendable, CaseIterable {
    /// Walking pace across the frame: 1/250 or faster.
    case walking
    /// Running, or close to the camera: 1/500 or faster.
    case running
    /// A passing vehicle at a typical street distance: 1/1000 or faster —
    /// crossing the frame far faster than a person can, even though it is not
    /// closer.
    case driving

    /// Slowest shutter that still freezes it, seconds.
    public var slowestShutter: TimeInterval {
        switch self {
        case .walking: 1.0 / 250
        case .running: 1.0 / 500
        case .driving: 1.0 / 1_000
        }
    }
}

/// What the photographer is trying to do, `docs/EXPOSURE-MODEL.md` §7.
public enum ExposureStrategy: Sendable, Equatable {
    /// Maximise depth so the lens can be pre-set and never focused.
    case zoneFocus
    /// Stop the subject dead, then take whatever depth is left.
    case freezeMotion(SubjectMotion)
    /// Widest aperture; shutter only fast enough to be safe.
    case subjectIsolation
    /// Lowest ISO that keeps the shutter at the handheld floor.
    case availableLight
    /// Pick the aperture; the body picks a stepless shutter.
    ///
    /// Only an M7 in this roster can be set this way. The answer is an aperture
    /// and a compensation dial setting rather than a shutter speed, because the
    /// ±1/3 stop quantisation of a doubling dial simply does not apply — the
    /// body can land on the aim exactly.
    case aperturePriority

    /// Whether a body can actually be set this way.
    public func isAvailable(on body: CameraBodyProfile) -> Bool {
        guard self == .aperturePriority else { return true }
        // A flat battery takes the automatic shutter with it: what is left on an
        // M7 is 1/60 and 1/125, mechanically.
        return body.supportsAperturePriority && body.shutterMode != .flatBattery
    }
}

/// How steadily the camera can be held, which sets the slowest usable shutter.
public enum HandheldSteadiness: String, Sendable, CaseIterable {
    /// The standard rule: `1/focal`.
    case standard
    /// A rangefinder has no mirror slap, so `1/(2·focal)` is genuinely holdable.
    /// Offer it; default it off.
    case rangefinder

    /// Slowest handholdable shutter for a focal length, seconds.
    public func floor(focalLengthMillimetres f: Double) -> TimeInterval {
        switch self {
        case .standard: 1 / f
        case .rangefinder: 2 / f
        }
    }
}

/// Everything the solver needs.
public struct ExposureRequest: Sendable, Equatable {
    public var ev100: Double
    public var body: CameraBodyProfile
    public var lens: LensProfile
    public var strategy: ExposureStrategy
    /// Slowest shutter the photographer will accept, seconds. Defaults to the
    /// `1/focal` rule for the lens.
    public var handheldFloor: TimeInterval
    /// When set, the zone is reported at the engraved mark nearest this
    /// distance; otherwise the solver picks the mark that reaches infinity.
    public var subjectDistanceMetres: Double?
    /// The aperture the photographer has turned the ring to under aperture
    /// priority. `nil` lets the solver pick one, and it picks for depth.
    /// Ignored by every other strategy, where the aperture is an output.
    public var chosenAperture: Double?
    /// How precisely the ladders can hit the aim at all: whole aperture stops
    /// and a doubling shutter dial cannot do better than ±1/3 stop. The medium
    /// narrows this further where it has less latitude — see
    /// ``ExposureTolerance`` and §7a. It is not the whole tolerance on its own.
    public var toleranceEV: Double

    public init(
        ev100: Double,
        body: CameraBodyProfile,
        lens: LensProfile,
        strategy: ExposureStrategy,
        handheldFloor: TimeInterval? = nil,
        subjectDistanceMetres: Double? = nil,
        chosenAperture: Double? = nil,
        toleranceEV: Double = 1.0 / 3
    ) {
        self.ev100 = ev100
        self.body = body
        self.lens = lens
        self.strategy = strategy
        self.handheldFloor = handheldFloor
            ?? HandheldSteadiness.standard.floor(focalLengthMillimetres: lens.focalLengthMillimetres)
        self.subjectDistanceMetres = subjectDistanceMetres
        self.chosenAperture = chosenAperture
        self.toleranceEV = toleranceEV
    }

    /// What the light lands on, which decides the tolerance and the aim.
    public var medium: Medium { body.medium }

    /// The asymmetric band around the aim, §7a.
    public var tolerance: ExposureTolerance {
        ExposureTolerance(medium: medium, precisionEV: toleranceEV)
    }

    /// `EV_target = EV_scene − bias`. Negative film is deliberately given more
    /// light than a meter would suggest; slide and digital slightly less.
    public var targetEV100: Double { ev100 - medium.biasEV }
}

/// One settable answer: aperture, shutter, ISO, and what it gives.
public struct ExposureRecommendation: Sendable, Equatable {
    public let aperture: Double
    /// Shutter time in seconds — `1/250`, not `250`.
    public let shutter: TimeInterval
    public let iso: Int
    /// Signed error against the **meter reading**, in stops. Negative is more
    /// light than the meter asks for.
    public let errorEV: Double
    /// Signed error against the medium's aim, `EV_scene − bias`. This is what
    /// the tolerance is applied to and what the ranking prefers; `errorEV` is
    /// what a meter would read, and the two differ by the bias, §7a.
    public let aimErrorEV: Double
    /// The zone this setting gives at the recommended engraved mark.
    public let zone: FocusRange?
    /// Set when the body chose the shutter itself: the compensation dial
    /// setting, in stops, that the app is actually asking for.
    ///
    /// When this is present ``shutter`` is what the body will land on rather
    /// than a speed to set — it is stepless, so it is a prediction, not an
    /// instruction, and the UI phrases it that way.
    public let compensationEV: Double?

    public init(
        aperture: Double,
        shutter: TimeInterval,
        iso: Int,
        errorEV: Double,
        aimErrorEV: Double? = nil,
        zone: FocusRange?,
        compensationEV: Double? = nil
    ) {
        self.aperture = aperture
        self.shutter = shutter
        self.iso = iso
        self.errorEV = errorEV
        self.aimErrorEV = aimErrorEV ?? errorEV
        self.zone = zone
        self.compensationEV = compensationEV
    }

    /// Whether the shutter is the body's own, chosen steplessly.
    public var isAutomatic: Bool { compensationEV != nil }
}

/// A solved recommendation plus the near misses worth offering.
public struct ExposureSolution: Sendable, Equatable {
    public let primary: ExposureRecommendation
    /// Neighbouring solutions, best first. The UI shows three or four.
    public let alternatives: [ExposureRecommendation]
    /// The engraved mark every zone above is reported for, metres.
    public let focusMarkMetres: Double?
    /// Set when the lens's widest aperture is off the dial at this light — the
    /// isolation case §7b insists is stated rather than quietly narrowed.
    public let wideOpen: UnreachableAperture?

    public init(
        primary: ExposureRecommendation,
        alternatives: [ExposureRecommendation],
        focusMarkMetres: Double?,
        wideOpen: UnreachableAperture? = nil
    ) {
        self.primary = primary
        self.alternatives = alternatives
        self.focusMarkMetres = focusMarkMetres
        self.wideOpen = wideOpen
    }

    /// How many settings there are in total: the row that reads "3 of 3" is
    /// literal, and the whole point is that it sometimes reads "2 of 2".
    public var count: Int { 1 + alternatives.count }
}

/// Why no setting could be found.
public enum ExposureSolverError: Error, Equatable, Sendable {
    /// Nothing on the body's ladders lands within tolerance of the target EV —
    /// the light is outside what this gear can expose. Open up, change film, or
    /// accept a slower shutter.
    case noSettingWithinTolerance(targetEV: Double, toleranceEV: Double)
    /// Settings exist, but the strategy's hard constraints rule all of them out.
    case strategyConstraintsUnsatisfiable(ExposureStrategy)
    /// The strategy is not something this body can be set to — aperture
    /// priority on anything but an M7.
    case strategyUnavailableOnBody(ExposureStrategy)
    /// The gear profile has no shutter speeds, apertures or ISO to work with.
    case emptyGearProfile
}

/// The exposure solver, `docs/EXPOSURE-MODEL.md` §7.
public enum ExposureSolver {
    /// Exposure value of a setting: `EV = log2(N² / t)`, with `t` in seconds.
    public static func exposureValue(aperture N: Double, shutter t: TimeInterval) -> Double {
        log2(N * N / t)
    }

    /// The EV a scene of `ev100` presents at a given sensitivity:
    /// `EV_S = EV100 + log2(S / 100)`.
    public static func exposureValue(ev100: Double, iso S: Int) -> Double {
        ev100 + log2(Double(S) / 100)
    }

    /// EV100 measured from a live setting, §8:
    /// `EV100 = log2(N² / t) − log2(S / 100)`.
    public static func measuredEV100(aperture N: Double, shutter t: TimeInterval, iso S: Int) -> Double {
        exposureValue(aperture: N, shutter: t) - log2(Double(S) / 100)
    }

    /// Solve for a setting.
    ///
    /// Enumerates the body's real shutter ladder against the lens's real
    /// aperture stops and the ISO it can offer, keeps everything inside the
    /// medium's asymmetric tolerance around `EV_scene − bias`, applies the
    /// strategy's hard constraints, then ranks.
    ///
    /// Never returns an empty list: when nothing lands, the answer is a
    /// ``ExposureShortfall`` naming the gap and the levers, because on a fixed
    /// roll *"HP5 400 is 0.9 stops short here"* is the useful thing to say, §7b.
    public static func resolve(_ request: ExposureRequest) -> ExposureOutcome {
        resolve(request, offeringLevers: true)
    }

    /// The throwing form, for callers that only want a setting. `solve` and
    /// `resolve` are the same solve; this one collapses the shortfall to the
    /// reason it carries.
    public static func solve(_ request: ExposureRequest) throws -> ExposureSolution {
        switch resolve(request) {
        case let .solved(solution): return solution
        case let .noSolution(shortfall): throw shortfall.reason
        }
    }

    private static func resolve(_ request: ExposureRequest, offeringLevers: Bool) -> ExposureOutcome {
        let isoValues = request.body.iso.solvableValues
        guard !request.body.shutterSpeeds.isEmpty, !request.lens.apertures.isEmpty, !isoValues.isEmpty else {
            return .noSolution(
                ExposureShortfall(
                    stops: 0,
                    aimStops: 0,
                    sense: .needsMoreLight,
                    closest: nil,
                    levers: offeringLevers ? ceilingLevers(request) : [],
                    reason: .emptyGearProfile
                )
            )
        }

        guard request.strategy.isAvailable(on: request.body) else {
            return .noSolution(
                ExposureShortfall(
                    stops: 0,
                    aimStops: 0,
                    sense: .needsMoreLight,
                    closest: nil,
                    levers: [],
                    reason: .strategyUnavailableOnBody(request.strategy)
                )
            )
        }

        let candidates = enumerate(request, isoValues: isoValues)
        let tolerance = request.tolerance
        let withinTolerance = candidates.filter { tolerance.accepts(aimErrorEV: $0.aimErrorEV) }
        let allowed = withinTolerance.filter { satisfiesHardConstraints($0, request) }

        guard !allowed.isEmpty else {
            let reason: ExposureSolverError = withinTolerance.isEmpty
                ? .noSettingWithinTolerance(targetEV: request.ev100, toleranceEV: request.toleranceEV)
                : .strategyConstraintsUnsatisfiable(request.strategy)
            return .noSolution(
                shortfall(for: request, candidates: candidates, reason: reason, offeringLevers: offeringLevers)
            )
        }
        let ranked = allowed.sorted { lhs, rhs in
            let l = score(lhs, request)
            let r = score(rhs, request)
            if l == r { return abs(lhs.aimErrorEV) < abs(rhs.aimErrorEV) }
            return l < r
        }

        // Every zone is reported for one engraved mark — the one the primary
        // answer asks for — so the alternatives show the depth collapsing as the
        // aperture opens rather than comparing different barrel settings.
        let mark = focusMark(for: ranked[0].aperture, request: request)

        return .solved(
            ExposureSolution(
                primary: recommendation(ranked[0], request: request, markMetres: mark),
                alternatives: ranked.dropFirst().map { recommendation($0, request: request, markMetres: mark) },
                focusMarkMetres: mark,
                wideOpen: unreachableWideOpen(request, iso: ranked[0].iso)
            )
        )
    }

    // MARK: - Enumeration

    private static func enumerate(_ request: ExposureRequest, isoValues: [Int]) -> [Candidate] {
        if request.strategy == .aperturePriority {
            return enumerateAperturePriority(request, isoValues: isoValues)
        }
        var candidates: [Candidate] = []
        for iso in isoValues {
            let metered = exposureValue(ev100: request.ev100, iso: iso)
            let aim = exposureValue(ev100: request.targetEV100, iso: iso)
            for shutter in request.body.shutterSpeeds where shutter > 0 {
                for aperture in request.lens.apertures where aperture > 0 {
                    let value = exposureValue(aperture: aperture, shutter: shutter)
                    candidates.append(
                        Candidate(
                            aperture: aperture,
                            shutter: shutter,
                            iso: iso,
                            errorEV: value - metered,
                            aimErrorEV: value - aim
                        )
                    )
                }
            }
        }
        return candidates
    }

    /// Aperture priority: the ring is the only thing the photographer sets.
    ///
    /// The body's shutter is stepless, so it lands on the metered value exactly
    /// and the ±1/3 stop quantisation of a doubling dial does not apply. What
    /// the app supplies instead is the **compensation dial** setting that moves
    /// the body's aim onto the medium's, §7a — so the answer is an aperture and
    /// a compensation, and the shutter below is a prediction of what the body
    /// will choose rather than something to set.
    ///
    /// Beyond the ends of the AE range the shutter is clamped, exactly as the
    /// camera clamps it, and the resulting error is what makes the outcome a
    /// shortfall rather than a setting.
    private static func enumerateAperturePriority(
        _ request: ExposureRequest,
        isoValues: [Int]
    ) -> [Candidate] {
        guard let fastest = request.body.fastestShutter,
              let slowest = request.body.slowestShutter
        else { return [] }

        let compensation = compensationSetting(for: request)
        let apertures = request.lens.apertures.filter { aperture in
            guard aperture > 0 else { return false }
            guard let chosen = request.chosenAperture else { return true }
            return abs(aperture - chosen) < 1e-9
        }

        var candidates: [Candidate] = []
        for iso in isoValues {
            let metered = exposureValue(ev100: request.ev100, iso: iso)
            let aim = exposureValue(ev100: request.targetEV100, iso: iso)
            for aperture in apertures {
                let wanted = aperture * aperture / pow(2, metered - compensation)
                let shutter = min(max(wanted, fastest), slowest)
                let value = exposureValue(aperture: aperture, shutter: shutter)
                candidates.append(
                    Candidate(
                        aperture: aperture,
                        shutter: shutter,
                        iso: iso,
                        errorEV: value - metered,
                        aimErrorEV: value - aim,
                        compensationEV: compensation
                    )
                )
            }
        }
        return candidates
    }

    /// The compensation dial setting, in stops: the medium's bias, snapped to
    /// the third-of-a-stop clicks the dial actually has and held inside its
    /// ±2 EV range.
    static func compensationSetting(for request: ExposureRequest) -> Double {
        let clicks = (request.medium.biasEV / compensationClickEV).rounded()
        let stops = clicks * compensationClickEV
        return min(max(stops, -compensationRangeEV), compensationRangeEV)
    }

    /// An exposure-compensation dial clicks in thirds of a stop.
    public static let compensationClickEV = 1.0 / 3
    /// And runs to ±2 stops.
    public static let compensationRangeEV = 2.0

    private static func recommendation(
        _ candidate: Candidate,
        request: ExposureRequest,
        markMetres: Double?
    ) -> ExposureRecommendation {
        ExposureRecommendation(
            aperture: candidate.aperture,
            shutter: candidate.shutter,
            iso: candidate.iso,
            errorEV: candidate.errorEV,
            aimErrorEV: candidate.aimErrorEV,
            zone: markMetres.map {
                ZoneFocus.range(
                    lens: request.lens,
                    body: request.body,
                    markMetres: $0,
                    aperture: candidate.aperture
                )
            },
            compensationEV: candidate.compensationEV
        )
    }

    // MARK: - No solution

    private static func shortfall(
        for request: ExposureRequest,
        candidates: [Candidate],
        reason: ExposureSolverError,
        offeringLevers: Bool
    ) -> ExposureShortfall {
        let constrained = candidates.filter { satisfiesHardConstraints($0, request) }
        let pool = constrained.isEmpty ? candidates : constrained
        let closest = pool.min { abs($0.errorEV) < abs($1.errorEV) }

        guard let closest else {
            return ExposureShortfall(
                stops: 0,
                aimStops: 0,
                sense: .needsMoreLight,
                closest: nil,
                levers: [],
                reason: reason
            )
        }

        let mark = focusMark(for: closest.aperture, request: request)
        return ExposureShortfall(
            stops: abs(closest.errorEV),
            aimStops: abs(closest.aimErrorEV),
            // A positive error means the setting wants more light than the scene
            // has: the roll is short. Negative is the bright-sun case.
            sense: closest.errorEV > 0 ? .needsMoreLight : .needsLessLight,
            closest: recommendation(closest, request: request, markMetres: mark),
            levers: offeringLevers ? levers(for: request, closest: closest) : [],
            reason: reason
        )
    }

    /// What would work, in the order §7b gives: rate the roll, move the floor,
    /// take light away, change film. Each one is re-solved rather than asserted,
    /// so a lever on screen is a lever that leads to a setting.
    private static func levers(for request: ExposureRequest, closest: Candidate) -> [ExposureLever] {
        var levers: [ExposureLever] = []
        let needsMoreLight = closest.errorEV > 0
        // Push comes in whole stops and has to close the gap to the *aim*, not
        // to the meter: on negative film the aim is already a third to two
        // thirds of a stop more light than the meter asks for.
        let wholeStops = max(1, Int(abs(closest.aimErrorEV).rounded(.up)))

        // Bounded before it is shifted: a scene ten stops under an ISO 25 roll
        // would otherwise ask for a rating no arithmetic can hold.
        if needsMoreLight, let roll = request.body.loadedRoll,
           wholeStops <= LoadedRoll.pushRange.upperBound {
            let pushed = LoadedRoll(stock: roll.stock, ratedAt: roll.ratedAt << wholeStops)
            if pushed.pushStops <= Double(LoadedRoll.pushRange.upperBound) + 0.01 {
                levers.append(.rate(roll: pushed, setting: bestSetting(request, iso: .fixed(pushed))))
            }
        }

        if needsMoreLight, let floorLever = slowerFloorLever(request) {
            levers.append(floorLever)
        }

        if !needsMoreLight {
            levers.append(.neutralDensity(stops: max(1, Int(abs(closest.aimErrorEV).rounded(.up)))))
        }

        // Past two stops the honest answer is that this is the wrong film for
        // this light, whatever the development can rescue.
        if let roll = request.body.loadedRoll, abs(closest.errorEV) > 2 {
            let wanted = Double(roll.ratedAt) * pow(2, needsMoreLight ? abs(closest.aimErrorEV) : -abs(closest.aimErrorEV))
            levers.append(
                .differentRoll(
                    isoSpeed: standardFilmSpeed(atLeast: wanted, faster: needsMoreLight),
                    faster: needsMoreLight
                )
            )
        }

        // Last, because on a sensor it is the only one that ever applies and the
        // order is the one `docs/SPEC-light.md` "When nothing works" states.
        levers.append(contentsOf: ceilingLevers(request))

        return levers
    }

    /// The digital case: it is the ceiling in the way, not the sensor, §7d.
    private static func ceilingLevers(_ request: ExposureRequest) -> [ExposureLever] {
        guard case let .range(minimum, maximum, ceiling) = request.body.iso, ceiling < maximum else { return [] }
        let uncapped = ISOAvailability.range(minimum: minimum, maximum: maximum, ceiling: maximum)
        var body = request.body
        body.iso = uncapped
        var uncappedRequest = request
        uncappedRequest.body = body
        guard case let .solved(solution) = resolve(uncappedRequest, offeringLevers: false) else { return [] }
        guard solution.primary.iso > ceiling else { return [] }
        return [.raiseCeiling(toISO: solution.primary.iso)]
    }

    /// Accepting a slower shutter than the floor is the second lever: the app
    /// offers the fastest speed that actually solves, so the blur is the least
    /// the scene allows.
    private static func slowerFloorLever(_ request: ExposureRequest) -> ExposureLever? {
        let slower = request.body.shutterSpeeds
            .filter { $0 > request.handheldFloor + 1e-12 }
            .sorted()
        for shutter in slower {
            var relaxed = request
            relaxed.handheldFloor = shutter
            if case let .solved(solution) = resolve(relaxed, offeringLevers: false),
               solution.primary.shutter >= shutter - 1e-12 {
                return .lowerFloor(shutter: shutter, setting: solution.primary)
            }
        }
        return nil
    }

    private static func bestSetting(_ request: ExposureRequest, iso: ISOAvailability) -> ExposureRecommendation? {
        var body = request.body
        body.iso = iso
        var rerun = request
        rerun.body = body
        return resolve(rerun, offeringLevers: false).solution?.primary
    }

    /// The speeds film is actually sold at. A recommendation to load ISO 1100 is
    /// not a recommendation.
    static let filmSpeeds = [25, 50, 100, 125, 160, 200, 400, 800, 1600, 3200]

    private static func standardFilmSpeed(atLeast wanted: Double, faster: Bool) -> Int {
        if faster {
            return filmSpeeds.first { Double($0) >= wanted - 1e-9 } ?? filmSpeeds.last ?? 3_200
        }
        return filmSpeeds.last { Double($0) <= wanted + 1e-9 } ?? filmSpeeds.first ?? 25
    }

    // MARK: - ISO as the solved variable, §7d

    /// The ISO a setting needs exactly: `S = 100 · 2^(log2(N²/t) − EV100)`.
    public static func requiredISO(ev100: Double, aperture: Double, shutter: TimeInterval) -> Double {
        100 * pow(2, exposureValue(aperture: aperture, shutter: shutter) - ev100)
    }

    /// Solve for the ISO on a digital body, rounded **up** to the body's next
    /// real step and reported against the user's ceiling, §7d.
    ///
    /// Returns `nil` on a fixed roll, where the ISO is not a variable at all.
    public static func solveISO(
        ev100: Double,
        aperture: Double,
        shutter: TimeInterval,
        availability: ISOAvailability
    ) -> ISORecommendation? {
        guard case .range = availability else { return nil }
        let ladder = availability.availableValues
        guard !ladder.isEmpty else { return nil }

        let exact = requiredISO(ev100: ev100, aperture: aperture, shutter: shutter)
        // Up, never down: down is under-exposure, and on digital that is the
        // direction with the least shadow latitude — and the one habit reaches
        // for.
        let stepped = ladder.first { Double($0) >= exact - 1e-9 } ?? ladder[ladder.count - 1]
        let capped = availability.solvableValues.last.map { min(stepped, $0) } ?? stepped
        return ISORecommendation(
            exact: exact,
            iso: capped,
            exceedsCeiling: exact > Double(capped) + 1e-9
        )
    }

    /// Whether an aperture is off the dial at this light: f/2 in bright sun on
    /// ISO 400 wants 1/35 120 s and no M has it, §7b.
    public static func unreachableAperture(
        ev100: Double,
        aperture: Double,
        iso: Int,
        body: CameraBodyProfile
    ) -> UnreachableAperture? {
        guard let fastest = body.fastestShutter else { return nil }
        let required = aperture * aperture / pow(2, exposureValue(ev100: ev100, iso: iso))
        guard required < fastest - 1e-12 else { return nil }
        return UnreachableAperture(
            aperture: aperture,
            iso: iso,
            requiredShutter: required,
            fastestShutter: fastest,
            neutralDensityStops: log2(fastest / required)
        )
    }

    private static func unreachableWideOpen(_ request: ExposureRequest, iso: Int) -> UnreachableAperture? {
        guard let widest = request.lens.apertures.filter({ $0 > 0 }).min() else { return nil }
        return unreachableAperture(
            ev100: request.ev100,
            aperture: widest,
            iso: iso,
            body: request.body
        )
    }

    // MARK: - Ranking

    struct Candidate: Equatable {
        let aperture: Double
        let shutter: TimeInterval
        let iso: Int
        /// Against the meter reading.
        let errorEV: Double
        /// Against the medium's aim, `EV_scene − bias`.
        let aimErrorEV: Double
        /// The compensation dial setting, when the body chose the shutter.
        var compensationEV: Double? = nil
    }

    /// Mild penalty outside f/5.6–f/11, where the lens is sharpest. Never a hard
    /// constraint — a diffraction-soft frame beats a missed one.
    static let optimalApertureRange = 5.6...11.0
    static let optimalAperturePenalty = 0.15

    private static func satisfiesHardConstraints(_ candidate: Candidate, _ request: ExposureRequest) -> Bool {
        switch request.strategy {
        case .zoneFocus:
            return candidate.shutter <= request.handheldFloor + 1e-12
        case let .freezeMotion(motion):
            let limit = min(request.handheldFloor, motion.slowestShutter)
            return candidate.shutter <= limit + 1e-12
        case .aperturePriority:
            // The body will choose whatever it likes; the only thing that rules
            // a candidate out is a shutter the photographer cannot hold.
            return candidate.shutter <= request.handheldFloor + 1e-12
        case .subjectIsolation, .availableLight:
            // No hard constraint; the ranking below prefers a safe shutter.
            return true
        }
    }

    /// Lower is better.
    private static func score(_ candidate: Candidate, _ request: ExposureRequest) -> Double {
        let apertureStops = log2(candidate.aperture)
        let isoStops = log2(Double(candidate.iso) / 100)
        let shutterStopsBelowFloor = max(0, log2(candidate.shutter / request.handheldFloor))

        var score = 0.5 * abs(candidate.aimErrorEV)
        if !optimalApertureRange.contains(candidate.aperture) {
            score += optimalAperturePenalty
        }

        switch request.strategy {
        case .zoneFocus, .freezeMotion, .aperturePriority:
            // Maximise depth: the smallest aperture that still meters. The ISO
            // term outweighs the aperture term so the solver does not buy depth
            // by pushing a digital sensor up the ISO ladder.
            score += -apertureStops + 1.5 * isoStops
        case .subjectIsolation:
            // Widest aperture; a shutter slower than the floor is discouraged
            // rather than forbidden.
            score += apertureStops + 0.5 * isoStops + 2.0 * shutterStopsBelowFloor
        case .availableLight:
            // Lowest ISO that still keeps the shutter at the handheld floor: the
            // floor dominates, and the ISO term then pushes back down the ladder.
            score += isoStops + 3.0 * shutterStopsBelowFloor
        }
        return score
    }

    private static func focusMark(for aperture: Double, request: ExposureRequest) -> Double? {
        if let subjectDistance = request.subjectDistanceMetres {
            return ZoneFocus.nearestMark(to: subjectDistance, on: request.lens)
        }
        return ZoneFocus.hyperfocalMark(lens: request.lens, body: request.body, aperture: aperture)
    }
}
