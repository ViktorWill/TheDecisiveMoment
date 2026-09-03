import Foundation
import Testing
@testable import TDMLight

@Suite("Phrasing — SPEC-light honesty rules")
struct ExposurePhrasingTests {
    @Test("Shutter speeds read as fractions of a second, never as integers")
    func phrasesShutter() {
        #expect(ExposurePhrasing.shutter(1.0 / 250) == "1/250")
        #expect(ExposurePhrasing.shutter(1.0 / 15) == "1/15")
        #expect(ExposurePhrasing.shutter(1) == "1 s")
        #expect(ExposurePhrasing.shutter(15) == "15 s")
    }

    @Test("Beyond the daylight σ the recommendation is hedged, not sharpened")
    func hedgesWhenUncertain() {
        #expect(ExposurePhrasing.shutter(1.0 / 250, sigmaEV: 0.5) == "1/250")
        #expect(ExposurePhrasing.shutter(1.0 / 250, sigmaEV: 0.8) == "1/250")
        #expect(ExposurePhrasing.shutter(1.0 / 30, sigmaEV: 1.5) == "about 1/30")
    }

    @Test("Half-stop clicks keep their decimal, full stops do not")
    func phrasesAperture() {
        #expect(ExposurePhrasing.aperture(8) == "f/8")
        #expect(ExposurePhrasing.aperture(6.7) == "f/6.7")
        #expect(ExposurePhrasing.aperture(1.4) == "f/1.4")
    }

    @Test("The worked example of §7 reads as the spec writes it")
    func phrasesTheAnswer() {
        #expect(
            ExposurePhrasing.setting(aperture: 8, shutter: 1.0 / 250, iso: 400, sigmaEV: 0.5)
                == "f/8 · 1/250 · ISO 400"
        )
        #expect(
            ExposurePhrasing.zoneSentence(markMetres: 3, near: 1.9, far: 7.16)
                == "scale to 3 m — sharp 1.9 to 7.2 m"
        )
        #expect(ExposurePhrasing.exposureValue(14.05, sigmaEV: 0.5) == "EV 14.1 ± 0.5")
    }

    @Test("A range that runs to infinity says so rather than naming a number")
    func phrasesInfinity() {
        #expect(
            ExposurePhrasing.zoneSentence(markMetres: .infinity, near: 1.4, far: .infinity)
                == "scale to ∞ — sharp 1.4 m to ∞"
        )
        #expect(ExposurePhrasing.distance(.infinity) == "∞")
    }

    @Test("Missing weather is stated, not silently replaced")
    func statesMissingWeather() {
        #expect(
            ExposurePhrasing.conditions(sunElevationDegrees: 14.727, cloudCover: 0.2)
                == "sun 14.7° · 20% cloud"
        )
        #expect(
            ExposurePhrasing.conditions(sunElevationDegrees: 14.727, cloudCover: 0.2, isStale: true)
                == "sun 14.7° · 20% cloud (stale)"
        )
        #expect(
            ExposurePhrasing.conditions(sunElevationDegrees: -3.2, cloudCover: nil)
                == "sun −3.2° · no weather — clear sky assumed"
        )
    }

    @Test("Computed distances lose their decimal where the maths cannot support it")
    func phrasesDistance() {
        #expect(ExposurePhrasing.sharpLimit(0.7) == "0.7 m")
        #expect(ExposurePhrasing.sharpLimit(3) == "3 m")
        #expect(ExposurePhrasing.sharpLimit(7.16) == "7.2 m")
        #expect(ExposurePhrasing.sharpLimit(183.4) == "183 m")
    }

    @Test("Countdowns stop at the minute")
    func phrasesCountdown() {
        #expect(ExposurePhrasing.countdown(30) == "now")
        #expect(ExposurePhrasing.countdown(42 * 60 + 20) == "in 42 min")
        #expect(ExposurePhrasing.countdown(2 * 3_600 + 5 * 60) == "in 2 h 05")
    }

    @Test("A stop difference carries its sign")
    func phrasesSignedStops() {
        #expect(ExposurePhrasing.signedStops(0.42) == "+0.4 EV")
        #expect(ExposurePhrasing.signedStops(-0.7) == "−0.7 EV")
    }

    @Test("A mark keeps its own value rather than being rounded into another")
    func neverRoundsAnEngravedMark() {
        #expect(ExposurePhrasing.distance(0.85) == "0.85 m")
        #expect(ExposurePhrasing.distance(0.7) == "0.7 m")
        #expect(ExposurePhrasing.distance(3) == "3 m")
        #expect(ExposurePhrasing.distance(122) == "122 m")
    }

    @Test("A computed depth-of-field limit is rounded like the estimate it is")
    func roundsComputedLimits() {
        #expect(ExposurePhrasing.sharpLimit(7.16) == "7.2 m")
        #expect(ExposurePhrasing.sharpLimit(41.3) == "41 m")
        #expect(ExposurePhrasing.sharpLimit(.infinity) == "∞")
    }

    @Test("The headline hedges when the estimate cannot support the digits")
    func hedgesTheHeadline() {
        #expect(
            ExposurePhrasing.setting(aperture: 2, shutter: 1.0 / 30, iso: 1600, sigmaEV: 1.5)
                == "f/2 · about 1/30 · ISO 1600"
        )
    }
}
