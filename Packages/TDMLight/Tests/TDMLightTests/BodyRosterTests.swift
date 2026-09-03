import Foundation
import Testing
import TDMCore
@testable import TDMLight

/// Every M from the M6 forward, as the solver sees it. The ladders and ISO
/// ranges are the roster in `docs/SPEC-light.md`; the expected numbers all come
/// from `docs/reference/body-vectors.py`.
enum Roster {
    static func shutterLadder(slowestSeconds: Int, fastestFraction: Int) -> [TimeInterval] {
        let slow: [TimeInterval] = [60, 30, 15, 8, 4, 2, 1].filter { $0 <= Double(slowestSeconds) }
        let fast: [TimeInterval] = [2, 4, 8, 15, 30, 60, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]
            .filter { $0 <= Double(fastestFraction) }
            .map { 1 / $0 }
        return (slow + fast).sorted()
    }

    static let m6 = CameraBodyProfile(
        name: "Leica M6",
        shutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        mechanicalFallbackShutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        iso: .fixed(400)
    )

    static let m7 = CameraBodyProfile(
        name: "Leica M7",
        shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 1_000),
        mechanicalFallbackShutterSpeeds: [1.0 / 125, 1.0 / 60],
        iso: .fixed(400),
        supportsAperturePriority: true
    )

    static let mp = CameraBodyProfile(
        name: "Leica MP",
        shutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        mechanicalFallbackShutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        iso: .fixed(400)
    )

    static let mA = CameraBodyProfile(
        name: "Leica M-A",
        shutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        mechanicalFallbackShutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
        iso: .fixed(400),
        hasMeter: false
    )

    static let m8 = CameraBodyProfile(
        name: "Leica M8",
        shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 8_000),
        iso: .range(minimum: 160, maximum: 2_500),
        format: .apsH
    )

    static let m9 = CameraBodyProfile(
        name: "Leica M9",
        shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 4_000),
        iso: .range(minimum: 80, maximum: 2_500)
    )

    static let m10 = CameraBodyProfile(
        name: "Leica M10",
        shutterSpeeds: shutterLadder(slowestSeconds: 8, fastestFraction: 4_000),
        iso: .range(minimum: 100, maximum: 50_000, ceiling: 6_400)
    )

    static let m11 = CameraBodyProfile(
        name: "Leica M11",
        shutterSpeeds: shutterLadder(slowestSeconds: 60, fastestFraction: 4_000),
        electronicShutterSpeeds: [1.0 / 16_000, 1.0 / 8_000],
        iso: .range(minimum: 64, maximum: 50_000, ceiling: 6_400)
    )

    static let all = [m6, m7, mp, mA, m8, m9, m10, m11]
}

@Suite("The M8 is not full frame — EXPOSURE-MODEL §6")
struct CroppedFormatTests {
    @Test("The circle of confusion is a property of the frame, not a constant")
    func circleOfConfusion() {
        #expect(abs(SensorFormat.fullFrame.circleOfConfusionMillimetres - 0.0300) < 0.00005)
        #expect(abs(SensorFormat.apsH.circleOfConfusionMillimetres - 0.0225) < 0.00005)
        // d/d₃₅ = 32.45 / 43.27.
        #expect(abs(SensorFormat.apsH.diagonalMillimetres - 32.45) < 0.01)
        #expect(abs(SensorFormat.fullFrame.diagonalMillimetres - 43.27) < 0.01)
        #expect(abs(Roster.m8.circleOfConfusionMillimetres - 0.0225) < 0.00005)
        #expect(abs(Roster.m9.circleOfConfusionMillimetres - 0.0300) < 0.00005)
    }

    @Test("35 mm and 50 mm at f/8, full frame and on the M8")
    func hyperfocals() {
        func H(_ f: Double, _ body: CameraBodyProfile) -> Double {
            DepthOfField.hyperfocalMetres(
                focalLengthMillimetres: f,
                aperture: 8,
                circleOfConfusionMillimetres: body.circleOfConfusionMillimetres
            )
        }
        #expect(abs(H(35, Roster.m9) - 5.14) <= 0.02)
        #expect(abs(H(35, Roster.m8) - 6.84) <= 0.02)
        #expect(abs(H(50, Roster.m9) - 10.47) <= 0.02)
        #expect(abs(H(50, Roster.m8) - 13.94) <= 0.02)
    }

    /// The whole of the M8's depth-of-field difference is one number: it sees a
    /// smaller circle of confusion by the ratio of the diagonals, so every
    /// hyperfocal is longer by the reciprocal. If this ever stops being exact,
    /// something has hardcoded a full-frame constant again.
    @Test("Every M8 hyperfocal is exactly 1.333x the full-frame one")
    func theRatioIsAnInvariant() {
        for f in [21.0, 28, 35, 50, 75, 90] {
            for N in [1.4, 2, 2.8, 4, 5.6, 8, 11, 16] {
                let fullFrame = DepthOfField.hyperfocalMillimetres(
                    focalLengthMillimetres: f,
                    aperture: N,
                    circleOfConfusionMillimetres: SensorFormat.fullFrame.circleOfConfusionMillimetres
                ) - f
                let cropped = DepthOfField.hyperfocalMillimetres(
                    focalLengthMillimetres: f,
                    aperture: N,
                    circleOfConfusionMillimetres: SensorFormat.apsH.circleOfConfusionMillimetres
                ) - f
                #expect(abs(cropped / fullFrame - 1.333) <= 0.001, "\(Int(f))mm f/\(N)")
            }
        }
    }

    @Test("35 mm f/8 at the 3 m mark is shallower on the M8")
    func theThreeMetreMark() {
        func zone(_ body: CameraBodyProfile) -> FocusRange {
            DepthOfField.range(
                focalLengthMillimetres: 35,
                aperture: 8,
                focusDistanceMetres: 3,
                circleOfConfusionMillimetres: body.circleOfConfusionMillimetres
            )
        }
        let fullFrame = zone(Roster.m9)
        #expect(abs(fullFrame.nearMetres - 1.90) <= 0.02)
        #expect(abs(fullFrame.farMetres - 7.16) <= 0.02)

        let cropped = zone(Roster.m8)
        #expect(abs(cropped.nearMetres - 2.09) <= 0.02)
        #expect(abs(cropped.farMetres - 5.32) <= 0.02)
    }

    /// Framing only. The crop factor multiplies the field of view and nothing
    /// else — it must never reach the exposure maths.
    @Test("A 35 mm frames like a 47 mm on the M8")
    func framing() {
        #expect(abs(SensorFormat.apsH.cropFactor - 1.333) <= 0.001)
        #expect(SensorFormat.apsH.equivalentFocalLengthMillimetres(35).rounded() == 47)
        #expect(SensorFormat.fullFrame.equivalentFocalLengthMillimetres(35) == 35)
        #expect(ExposurePhrasing.framing(focalLengthMillimetres: 35, format: .apsH) == "frames like a 47 mm")
        #expect(ExposurePhrasing.framing(focalLengthMillimetres: 35, format: .fullFrame) == nil)
    }
}

@Suite("What each body can reach — EXPOSURE-MODEL §7b, §7d")
struct BodyReachTests {
    /// f/2 in bright sun. At the slowest ISO each body offers, only the M11's
    /// electronic shutter is fast enough — its own mechanical shutter is not,
    /// so this generalises neither to "digital bodies" nor to "the M11".
    @Test("f/2 at EV100 15.10 is reachable on the M11's electronic shutter and nowhere else")
    func brightSunWideOpen() {
        func reaches(_ body: CameraBodyProfile) -> Bool {
            let iso = body.iso.availableValues.first ?? 100
            return ExposureSolver.unreachableAperture(ev100: 15.10, aperture: 2, iso: iso, body: body) == nil
        }
        for body in Roster.all {
            #expect(!reaches(body), "\(body.name) should not reach f/2 on its dial")
        }
        #expect(reaches(Roster.m11.using(.electronic)))

        // The exact figure behind it: 1/5619 at ISO 64, against 1/16000.
        let shortfall = try? #require(
            ExposureSolver.unreachableAperture(ev100: 15.10, aperture: 2, iso: 64, body: Roster.m11)
        )
        #expect(abs((shortfall?.requiredShutter ?? 0) - 1.0 / 5_619) < 1e-7)
    }

    /// A dim side street. Two generations of sensor is the difference between
    /// an answer and a shortfall — and the shortfall is a digital one, so the
    /// levers it offers must not include pushing a roll that is not there.
    @Test("f/2 · 1/125 at EV100 3.0 wants ISO 6250: the M8 and M9 are short")
    func dimStreetWideOpen() throws {
        #expect(abs(ExposureSolver.requiredISO(ev100: 3.0, aperture: 2, shutter: 1.0 / 125) - 6_250) < 1)

        // The question here is what the *sensor* has, not where the photographer
        // has set the ceiling: on the M8 and the M9 raising the ceiling would
        // not help, and that is what makes them short rather than capped.
        func sensorLimited(_ body: CameraBodyProfile) throws -> ISORecommendation {
            let sensor = try #require(body.iso.sensorRange)
            return try #require(
                ExposureSolver.solveISO(
                    ev100: 3.0,
                    aperture: 2,
                    shutter: 1.0 / 125,
                    availability: .range(minimum: sensor.minimum, maximum: sensor.maximum)
                )
            )
        }
        #expect(try sensorLimited(Roster.m8).exceedsCeiling)
        #expect(try sensorLimited(Roster.m9).exceedsCeiling)
        #expect(try !sensorLimited(Roster.m10).exceedsCeiling)
        #expect(try !sensorLimited(Roster.m11).exceedsCeiling)
        // Film has no ISO to solve for at all.
        #expect(ExposureSolver.solveISO(ev100: 3.0, aperture: 2, shutter: 1.0 / 125, availability: Roster.m6.iso) == nil)
    }

    @Test("A digital body that runs out of sensor is never offered a push")
    func digitalShortfallLevers() {
        var request = ExposureRequest(
            ev100: 3.0,
            body: Roster.m8,
            lens: TestGear.summicron35,
            strategy: .zoneFocus,
            handheldFloor: 1.0 / 125
        )
        request.toleranceEV = 1.0 / 3
        guard case let .noSolution(shortfall) = ExposureSolver.resolve(request) else {
            Issue.record("the M8 should be short at EV100 3.0 wide open")
            return
        }
        for lever in shortfall.levers {
            switch lever {
            case .rate, .differentRoll:
                Issue.record("a sensor cannot be pushed like a roll: \(lever)")
            default:
                break
            }
        }
        #expect(!shortfall.levers.isEmpty)
    }
}

@Suite("Aperture priority — the M7 only")
struct AperturePriorityTests {
    func request(ev100: Double = 12.0, aperture: Double = 8) -> ExposureRequest {
        var request = ExposureRequest(
            ev100: ev100,
            body: Roster.m7,
            lens: TestGear.summicron35,
            strategy: .aperturePriority,
            handheldFloor: 1.0 / 60
        )
        request.chosenAperture = aperture
        return request
    }

    @Test("The strategy exists only on a body that has it")
    func gatedOnTheBody() {
        #expect(ExposureStrategy.aperturePriority.isAvailable(on: Roster.m7))
        for body in Roster.all where body.name != "Leica M7" {
            #expect(!ExposureStrategy.aperturePriority.isAvailable(on: body), "\(body.name)")
        }

        var unavailable = request()
        unavailable.body = Roster.m6
        guard case let .noSolution(shortfall) = ExposureSolver.resolve(unavailable) else {
            Issue.record("an M6 cannot be put in A")
            return
        }
        #expect(shortfall.reason == ExposureSolverError.strategyUnavailableOnBody(.aperturePriority))
    }

    /// The body's shutter is stepless, so the answer is not on the dial and the
    /// ±1/3 stop quantisation of §7 does not apply: the error is exactly the
    /// compensation the photographer dials in.
    @Test("The shutter is stepless, so the answer is an aperture and a compensation")
    func steplessShutter() throws {
        let solution = try ExposureSolver.solve(request(ev100: 12.0, aperture: 8))
        #expect(solution.primary.aperture == 8)
        #expect(solution.primary.isAutomatic)

        let compensation = try #require(solution.primary.compensationEV)
        // A third of a stop of film's highlight bias, on the dial's clicks.
        #expect(abs(compensation.truncatingRemainder(dividingBy: ExposureSolver.compensationClickEV)) < 1e-9)
        #expect(abs(compensation) <= ExposureSolver.compensationRangeEV + 1e-9)

        // Stepless: N²/t lands exactly on the aim — `EV_metered − compensation`,
        // a third of a stop more light than the meter, which is where the aim
        // for a black-and-white negative is — and off the engraved ladder.
        let aimed = ExposureSolver.exposureValue(aperture: 8, shutter: solution.primary.shutter)
        let metered = ExposureSolver.exposureValue(ev100: 12.0, iso: 400)
        #expect(abs(compensation - 1.0 / 3) < 1e-9)
        #expect(abs(aimed - (metered - compensation)) < 1e-6)
        #expect(!Roster.m7.shutterSpeeds.contains { abs($0 - solution.primary.shutter) < 1e-12 })
    }

    @Test("A flat battery leaves 1/60 and 1/125, and the solver knows it")
    func flatBattery() {
        let dead = Roster.m7.using(.flatBattery)
        #expect(dead.shutterSpeeds == [1.0 / 125, 1.0 / 60])
        #expect(dead.fastestShutter == 1.0 / 125)
        // And with no electronics there is no automatic shutter either.
        #expect(!ExposureStrategy.aperturePriority.isAvailable(on: dead))
    }
}
