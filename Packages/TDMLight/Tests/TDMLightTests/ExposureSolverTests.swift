import Foundation
import Testing
import TDMCore
@testable import TDMLight

@Suite("Exposure solver — EXPOSURE-MODEL §7")
struct ExposureSolverTests {
    /// The document's worked solve: EV100 14.05, ISO 400 film, 35 mm,
    /// zone-focus strategy, handheld floor 1/125.
    func zoneFocusRequest() -> ExposureRequest {
        ExposureRequest(
            ev100: 14.05,
            body: TestGear.m6,
            lens: TestGear.summicron35,
            strategy: .zoneFocus,
            handheldFloor: 1.0 / 125
        )
    }

    @Test("The target EV at the loaded film speed")
    func targetExposureValue() {
        #expect(abs(ExposureSolver.exposureValue(ev100: 14.05, iso: 400) - 16.05) < 0.005)
        // N²/t = 2^16.05 ≈ 67 847.
        #expect(abs(pow(2, 16.05) - 67_847) < 1)
    }

    @Test("Zone focus recommends f/16 · 1/250, sharp 1.4 m to infinity at 3 m")
    func zoneFocusSolve() throws {
        let solution = try ExposureSolver.solve(zoneFocusRequest())

        #expect(solution.primary.aperture == 16)
        #expect(abs(solution.primary.shutter - 1.0 / 250) < 1e-12)
        #expect(solution.primary.iso == 400)
        #expect(abs(solution.primary.errorEV - (-0.08)) <= 0.005)
        #expect(solution.focusMarkMetres == 3.0)

        let zone = try #require(solution.primary.zone)
        #expect(abs(zone.nearMetres - 1.39) <= 0.02)
        #expect(zone.reachesInfinity)
    }

    @Test("The alternatives are f/11 · 1/500 and f/8 · 1/1000, at the same mark")
    func zoneFocusAlternatives() throws {
        let solution = try ExposureSolver.solve(zoneFocusRequest())
        #expect(solution.alternatives.count == 2)

        let f11 = try #require(solution.alternatives.first)
        #expect(f11.aperture == 11)
        #expect(abs(f11.shutter - 1.0 / 500) < 1e-12)
        #expect(abs(f11.errorEV - (-0.17)) <= 0.005)
        let f11Zone = try #require(f11.zone)
        #expect(abs(f11Zone.nearMetres - 1.67) <= 0.02)
        #expect(abs(f11Zone.farMetres - 14.9) <= 0.1)

        let f8 = try #require(solution.alternatives.last)
        #expect(f8.aperture == 8)
        #expect(abs(f8.shutter - 1.0 / 1000) < 1e-12)
        #expect(abs(f8.errorEV - (-0.08)) <= 0.005)
        let f8Zone = try #require(f8.zone)
        #expect(abs(f8Zone.nearMetres - 1.89) <= 0.02)
        #expect(abs(f8Zone.farMetres - 7.16) <= 0.02)
    }

    @Test("Every candidate is within a third of a stop and on the real ladders")
    func candidatesAreSettable() throws {
        let request = zoneFocusRequest()
        let solution = try ExposureSolver.solve(request)
        for recommendation in [solution.primary] + solution.alternatives {
            #expect(abs(recommendation.errorEV) <= 1.0 / 3 + 1e-9)
            #expect(request.lens.apertures.contains(recommendation.aperture))
            #expect(request.body.shutterSpeeds.contains { abs($0 - recommendation.shutter) < 1e-12 })
            #expect(recommendation.shutter <= request.handheldFloor)
        }
    }

    @Test("Freeze motion never returns a shutter slower than the motion allows")
    func freezeMotion() throws {
        var request = zoneFocusRequest()
        request.ev100 = 12.05
        request.strategy = .freezeMotion(.running)
        let solution = try ExposureSolver.solve(request)
        #expect(solution.primary.shutter <= SubjectMotion.running.slowestShutter + 1e-12)
        for alternative in solution.alternatives {
            #expect(alternative.shutter <= SubjectMotion.running.slowestShutter + 1e-12)
        }
    }

    @Test("Subject isolation opens the lens up, zone focus stops it down")
    func strategiesDisagree() throws {
        var request = zoneFocusRequest()
        request.strategy = .subjectIsolation
        let isolation = try ExposureSolver.solve(request)
        request.strategy = .zoneFocus
        let zone = try ExposureSolver.solve(request)
        #expect(isolation.primary.aperture < zone.primary.aperture)
    }

    @Test("Available light picks the lowest ISO that holds the handheld floor")
    func availableLight() throws {
        // Dusk on a digital body: ISO is the free variable.
        let request = ExposureRequest(
            ev100: 5.0,
            body: TestGear.m10,
            lens: TestGear.summicron35,
            strategy: .availableLight,
            handheldFloor: 1.0 / 60
        )
        let solution = try ExposureSolver.solve(request)
        #expect(solution.primary.shutter <= 1.0 / 60 + 1e-12)
        for alternative in solution.alternatives where alternative.shutter <= 1.0 / 60 + 1e-12 {
            #expect(solution.primary.iso <= alternative.iso)
        }
    }

    @Test("Zone focus does not buy depth by pushing a digital sensor up the ISO ladder")
    func zoneFocusPrefersLowISO() throws {
        let request = ExposureRequest(
            ev100: 14.05,
            body: TestGear.m10,
            lens: TestGear.summicron35,
            strategy: .zoneFocus,
            handheldFloor: 1.0 / 125
        )
        let solution = try ExposureSolver.solve(request)
        #expect(solution.primary.iso == 100)
    }

    @Test("The handheld floor follows 1/focal, or 1/2focal for a rangefinder")
    func handheldFloors() {
        #expect(abs(HandheldSteadiness.standard.floor(focalLengthMillimetres: 35) - 1.0 / 35) < 1e-12)
        #expect(abs(HandheldSteadiness.rangefinder.floor(focalLengthMillimetres: 35) - 1.0 / 17.5) < 1e-12)
        let request = ExposureRequest(
            ev100: 14.05,
            body: TestGear.m6,
            lens: TestGear.summicron35,
            strategy: .zoneFocus
        )
        #expect(abs(request.handheldFloor - 1.0 / 35) < 1e-12)
    }

    @Test("Light outside what the gear can expose is an error, not a wrong answer")
    func noSettingWithinTolerance() {
        let request = ExposureRequest(
            ev100: 25,
            body: TestGear.m6,
            lens: TestGear.summicron35,
            strategy: .zoneFocus
        )
        #expect(throws: ExposureSolverError.noSettingWithinTolerance(targetEV: 25, toleranceEV: 1.0 / 3)) {
            try ExposureSolver.solve(request)
        }
    }

    @Test("A strategy that cannot be satisfied says so")
    func strategyUnsatisfiable() {
        // Enough light for 1/60 at f/16 and no more; freezing a runner is out.
        let request = ExposureRequest(
            ev100: 8.0,
            body: TestGear.m6,
            lens: TestGear.summicron35,
            strategy: .freezeMotion(.running),
            handheldFloor: 1.0 / 60
        )
        #expect(throws: ExposureSolverError.strategyConstraintsUnsatisfiable(.freezeMotion(.running))) {
            try ExposureSolver.solve(request)
        }
    }

    @Test("A gear profile with nothing on its ladders is rejected")
    func emptyGear() {
        let body = CameraBodyProfile(name: "Empty", shutterSpeeds: [], iso: .fixed(100))
        let request = ExposureRequest(
            ev100: 12,
            body: body,
            lens: TestGear.summicron35,
            strategy: .zoneFocus
        )
        #expect(throws: ExposureSolverError.emptyGearProfile) {
            try ExposureSolver.solve(request)
        }
    }

    @Test("A subject distance overrides the hyperfocal mark, still snapped to the barrel")
    func subjectDistanceOverride() throws {
        var request = zoneFocusRequest()
        request.subjectDistanceMetres = 1.8
        let solution = try ExposureSolver.solve(request)
        #expect(solution.focusMarkMetres == 2.0)
    }

    @Test("A digital ISO range enumerates in full stops")
    func isoLadder() {
        #expect(ISOAvailability.fixed(400).availableValues == [400])
        #expect(ISOAvailability.range(minimum: 100, maximum: 6400).availableValues == [100, 200, 400, 800, 1600, 3200, 6400])
        #expect(ISOAvailability.range(minimum: 64, maximum: 200).availableValues == [64, 128])
    }

    @Test("Measured EV from a live setting inverts the solver's relation — §8")
    func measuredEVRoundTrip() throws {
        let solution = try ExposureSolver.solve(zoneFocusRequest())
        let measured = ExposureSolver.measuredEV100(
            aperture: solution.primary.aperture,
            shutter: solution.primary.shutter,
            iso: solution.primary.iso
        )
        #expect(abs(measured - (14.05 + solution.primary.errorEV)) < 1e-9)
    }
}

@Suite("Stored gear adapters")
struct StoredGearAdapterTests {
    @Test("A stored film body arrives at the solver with its roll speed intact")
    func adaptsFilmBody() {
        let stored = CameraBody(
            name: "Leica M6",
            shutterSpeeds: [1.0 / 250, 1, 1.0 / 1_000],
            iso: .fixed(400),
            hasMeter: true,
            loadedFilm: "Tri-X"
        )
        let profile = CameraBodyProfile(stored)

        #expect(profile.name == "Leica M6")
        #expect(profile.iso == .fixed(400))
        #expect(profile.shutterSpeeds == [1.0 / 1_000, 1.0 / 250, 1])
    }

    @Test("A stored lens keeps every engraved mark, ∞ included")
    func adaptsLens() {
        let stored = Lens(
            name: "Elmarit-M 90mm f/2.8",
            focalLengthMillimetres: 90,
            apertures: [2.8, 4, 5.6],
            distanceMarksMetres: [3.0, 1.0, .infinity, 1.5],
            minimumFocusMetres: 1.0
        )
        let profile = LensProfile(stored)

        #expect(profile.focalLengthMillimetres == 90)
        #expect(profile.sortedDistanceMarks.filter(\.isFinite) == [1.0, 1.5, 3.0])
        #expect(profile.distanceMarksMetres.contains { !$0.isFinite })
    }

    @Test("The stored strategy round-trips, carrying the motion it needs")
    func adaptsStrategy() {
        #expect(ExposureStrategy(.zoneFocus) == .zoneFocus)
        #expect(ExposureStrategy(.freezeMotion, motion: .running) == .freezeMotion(.running))
        #expect(ExposureStrategy(.freezeMotion).stored == StoredExposureStrategy.freezeMotion)
        for stored in StoredExposureStrategy.allCases {
            #expect(ExposureStrategy(stored).stored == stored)
        }
    }
}
