import Foundation

/// How fast the subject is moving, for the freeze-motion strategy.
public enum SubjectMotion: String, Sendable, CaseIterable {
    /// Walking pace across the frame: 1/250 or faster.
    case walking
    /// Running, or close to the camera: 1/500 or faster.
    case running

    /// Slowest shutter that still freezes it, seconds.
    public var slowestShutter: TimeInterval {
        switch self {
        case .walking: 1.0 / 250
        case .running: 1.0 / 500
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
    /// Candidates further than this from the target EV are discarded. §7 says
    /// ±1/3 stop.
    public var toleranceEV: Double

    public init(
        ev100: Double,
        body: CameraBodyProfile,
        lens: LensProfile,
        strategy: ExposureStrategy,
        handheldFloor: TimeInterval? = nil,
        subjectDistanceMetres: Double? = nil,
        toleranceEV: Double = 1.0 / 3
    ) {
        self.ev100 = ev100
        self.body = body
        self.lens = lens
        self.strategy = strategy
        self.handheldFloor = handheldFloor
            ?? HandheldSteadiness.standard.floor(focalLengthMillimetres: lens.focalLengthMillimetres)
        self.subjectDistanceMetres = subjectDistanceMetres
        self.toleranceEV = toleranceEV
    }
}

/// One settable answer: aperture, shutter, ISO, and what it gives.
public struct ExposureRecommendation: Sendable, Equatable {
    public let aperture: Double
    /// Shutter time in seconds — `1/250`, not `250`.
    public let shutter: TimeInterval
    public let iso: Int
    /// Signed error against the target, in stops. Negative is under-exposed.
    public let errorEV: Double
    /// The zone this setting gives at the recommended engraved mark.
    public let zone: FocusRange?

    public init(aperture: Double, shutter: TimeInterval, iso: Int, errorEV: Double, zone: FocusRange?) {
        self.aperture = aperture
        self.shutter = shutter
        self.iso = iso
        self.errorEV = errorEV
        self.zone = zone
    }
}

/// A solved recommendation plus the near misses worth offering.
public struct ExposureSolution: Sendable, Equatable {
    public let primary: ExposureRecommendation
    /// Neighbouring solutions, best first. The UI shows three or four.
    public let alternatives: [ExposureRecommendation]
    /// The engraved mark every zone above is reported for, metres.
    public let focusMarkMetres: Double?

    public init(
        primary: ExposureRecommendation,
        alternatives: [ExposureRecommendation],
        focusMarkMetres: Double?
    ) {
        self.primary = primary
        self.alternatives = alternatives
        self.focusMarkMetres = focusMarkMetres
    }
}

/// Why no setting could be found.
public enum ExposureSolverError: Error, Equatable, Sendable {
    /// Nothing on the body's ladders lands within tolerance of the target EV —
    /// the light is outside what this gear can expose. Open up, change film, or
    /// accept a slower shutter.
    case noSettingWithinTolerance(targetEV: Double, toleranceEV: Double)
    /// Settings exist, but the strategy's hard constraints rule all of them out.
    case strategyConstraintsUnsatisfiable(ExposureStrategy)
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
    /// aperture stops and the available ISO, keeps everything within the
    /// tolerance (±1/3 stop), applies the strategy's hard constraints, then
    /// ranks. Returns the primary answer and the neighbours worth offering.
    public static func solve(_ request: ExposureRequest) throws -> ExposureSolution {
        let isoValues = request.body.iso.availableValues
        guard !request.body.shutterSpeeds.isEmpty, !request.lens.apertures.isEmpty, !isoValues.isEmpty else {
            throw ExposureSolverError.emptyGearProfile
        }

        var withinTolerance: [(candidate: Candidate, passesStrategy: Bool)] = []
        for iso in isoValues {
            let target = exposureValue(ev100: request.ev100, iso: iso)
            for shutter in request.body.shutterSpeeds where shutter > 0 {
                for aperture in request.lens.apertures where aperture > 0 {
                    let error = exposureValue(aperture: aperture, shutter: shutter) - target
                    guard abs(error) <= request.toleranceEV + 1e-9 else { continue }
                    let candidate = Candidate(aperture: aperture, shutter: shutter, iso: iso, errorEV: error)
                    withinTolerance.append((candidate, satisfiesHardConstraints(candidate, request)))
                }
            }
        }

        guard !withinTolerance.isEmpty else {
            throw ExposureSolverError.noSettingWithinTolerance(
                targetEV: request.ev100,
                toleranceEV: request.toleranceEV
            )
        }
        let allowed = withinTolerance.filter(\.passesStrategy).map(\.candidate)
        guard !allowed.isEmpty else {
            throw ExposureSolverError.strategyConstraintsUnsatisfiable(request.strategy)
        }

        let ranked = allowed.sorted { lhs, rhs in
            let l = score(lhs, request)
            let r = score(rhs, request)
            if l == r { return abs(lhs.errorEV) < abs(rhs.errorEV) }
            return l < r
        }

        // Every zone is reported for one engraved mark — the one the primary
        // answer asks for — so the alternatives show the depth collapsing as the
        // aperture opens rather than comparing different barrel settings.
        let mark = focusMark(for: ranked[0].aperture, request: request)
        func recommendation(_ candidate: Candidate) -> ExposureRecommendation {
            ExposureRecommendation(
                aperture: candidate.aperture,
                shutter: candidate.shutter,
                iso: candidate.iso,
                errorEV: candidate.errorEV,
                zone: mark.map {
                    ZoneFocus.range(
                        lens: request.lens,
                        body: request.body,
                        markMetres: $0,
                        aperture: candidate.aperture
                    )
                }
            )
        }

        return ExposureSolution(
            primary: recommendation(ranked[0]),
            alternatives: ranked.dropFirst().map(recommendation),
            focusMarkMetres: mark
        )
    }

    // MARK: - Ranking

    struct Candidate: Equatable {
        let aperture: Double
        let shutter: TimeInterval
        let iso: Int
        let errorEV: Double
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

        var score = 0.5 * abs(candidate.errorEV)
        if !optimalApertureRange.contains(candidate.aperture) {
            score += optimalAperturePenalty
        }

        switch request.strategy {
        case .zoneFocus, .freezeMotion:
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
