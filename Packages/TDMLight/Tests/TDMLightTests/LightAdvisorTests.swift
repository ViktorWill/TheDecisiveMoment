import Foundation
import Testing
@testable import TDMLight

/// NYC, as in `docs/EXPOSURE-MODEL.md` §1 and §4.
private let manhattanLatitude = 40.7128
private let manhattanLongitude = -74.0060

private func request(
    date: Date,
    cloudCover: Double? = 0.2,
    scene: ScenePreset = .openSky,
    strategy: ExposureStrategy = .zoneFocus,
    body: CameraBodyProfile = TestGear.m6
) -> AdviceRequest {
    AdviceRequest(
        date: date,
        latitudeDegrees: manhattanLatitude,
        longitudeDegrees: manhattanLongitude,
        cloudCover: cloudCover,
        scene: scene,
        body: body,
        lens: TestGear.summicron35,
        strategy: strategy
    )
}

@Suite("Light advisor")
struct LightAdvisorTests {
    /// 21 June 2026, 19:00 EDT — the worked example of §4.
    private let summerEvening = Date(timeIntervalSince1970: 1_782_255_600)

    @Test("The chain runs sun → EV → setting → zone in one call")
    func composesTheWholeChain() {
        let advice = LightAdvisor.advise(request(date: summerEvening))

        #expect(advice.sun.elevationDegrees > 10)
        #expect(advice.estimate.ev100 > 13)
        #expect(advice.solution != nil)
        #expect(advice.solverError == nil)
        // Honesty rule 4: the mark is one the lens has.
        let mark = try? #require(advice.focusMarkMetres)
        #expect(mark.map { TestGear.summicron35.sortedDistanceMarks.contains($0) } ?? false)
    }

    @Test("A shaded street is darker than the sunlit side at the same moment")
    func sceneChangesTheAnswer() {
        let sunlit = LightAdvisor.advise(request(date: summerEvening, scene: .openSky))
        let shaded = LightAdvisor.advise(request(date: summerEvening, scene: .shadedSideOfStreet))

        #expect(abs((sunlit.estimate.ev100 - shaded.estimate.ev100) - 2.5) < 1e-9)
    }

    @Test("No weather means clear sky and a wider σ, not a refusal to answer")
    func missingWeatherStillAnswers() {
        // A digital body, so the extra stop of clear-sky light is still inside
        // what the gear can expose and the comparison is about σ alone.
        let withWeather = LightAdvisor.advise(request(date: summerEvening, body: TestGear.m10))
        let without = LightAdvisor.advise(
            request(date: summerEvening, cloudCover: nil, body: TestGear.m10)
        )

        #expect(withWeather.solution != nil)
        #expect(without.estimate.usedClearSkyFallback)
        #expect(without.estimate.ev100 > withWeather.estimate.ev100)
        #expect(without.estimate.sigmaEV > withWeather.estimate.sigmaEV)
        // §9: the fallback penalty is 0.7 EV in quadrature, not an excuse to
        // stop answering — the estimate is still there to act on.
        #expect(abs(without.estimate.sigmaEV - (0.8 * 0.8 + 0.7 * 0.7).squareRoot()) < 1e-9)
    }

    @Test("Light the gear cannot expose is reported, not faked")
    func reportsSolverFailure() {
        // 23:00 EDT on the same day, dim side street: EV100 2.5 is below what an
        // M6 loaded with ISO 400 film can reach on a 1/35 s handheld floor.
        var midnight = request(date: summerEvening.addingTimeInterval(4 * 3_600), cloudCover: 0)
        midnight.nightPreset = .dimSideStreet
        let advice = LightAdvisor.advise(midnight)

        #expect(advice.estimate.regime == .night)
        #expect(advice.solution == nil)
        #expect(advice.solverError != nil)
    }

    @Test("The scrubber gets one answer per hour, and says which hours lack weather")
    func hourlyRunsThePerHourModel() {
        let advices = LightAdvisor.hourly(
            from: summerEvening,
            hours: 12,
            request: request(date: summerEvening)
        ) { date in
            // Weather for the first four hours only, as a short forecast would be.
            date.timeIntervalSince(summerEvening) < 4 * 3_600
                ? (0.2, .fresh, .none)
                : (nil, .unavailable, .none)
        }

        #expect(advices.count == 12)
        #expect(advices.map(\.date) == advices.map(\.date).sorted())
        #expect(advices.prefix(4).allSatisfy { !$0.estimate.usedClearSkyFallback })
        #expect(advices.dropFirst(4).allSatisfy { $0.estimate.usedClearSkyFallback })
        // The sun sets over the twelve hours, so the EV falls.
        #expect(advices.last!.estimate.ev100 < advices.first!.estimate.ev100)
    }
}
