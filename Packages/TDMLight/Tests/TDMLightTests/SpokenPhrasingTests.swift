import Foundation
import Testing
import TDMCore
@testable import TDMLight

/// The readout has to be usable by ear: `f/8 · 1/250` said as "f slash 8, 1
/// slash 250" is not an exposure, it is a string.
@Suite("Spoken phrasing — VoiceOver on the Light screen")
struct SpokenPhrasingTests {
    @Test("Apertures lose the slash")
    func apertures() {
        #expect(ExposurePhrasing.spokenAperture(8) == "f 8")
        #expect(ExposurePhrasing.spokenAperture(1.4) == "f 1.4")
    }

    @Test("A fractional shutter is said as a fraction of a second")
    func fractionalShutter() {
        #expect(ExposurePhrasing.spokenShutter(1.0 / 250) == "1 over 250 of a second")
        #expect(ExposurePhrasing.spokenShutter(1.0 / 60) == "1 over 60 of a second")
    }

    @Test("A long exposure is said in seconds, singular where it should be")
    func longShutter() {
        #expect(ExposurePhrasing.spokenShutter(1) == "1 second")
        #expect(ExposurePhrasing.spokenShutter(15) == "15 seconds")
        #expect(ExposurePhrasing.spokenShutter(0) == "no shutter speed")
    }

    @Test("The hedge survives into speech")
    func hedged() {
        let wide = ExposurePhrasing.hedgeThresholdEV + 0.1
        #expect(ExposurePhrasing.spokenShutter(1.0 / 250, sigmaEV: wide) == "about 1 over 250 of a second")
        #expect(ExposurePhrasing.spokenShutter(1.0 / 250, sigmaEV: 0.3) == "1 over 250 of a second")
    }

    @Test("The headline reads as a sentence")
    func headline() {
        let spoken = ExposurePhrasing.spokenSetting(aperture: 8, shutter: 1.0 / 250, iso: 400, sigmaEV: 0.5)
        #expect(spoken == "f 8, 1 over 250 of a second, ISO 400")
    }

    @Test("Compensation is said in thirds, and zero is said as nothing to set")
    func compensation() {
        #expect(ExposurePhrasing.spokenCompensation(0) == "no exposure compensation")
        #expect(ExposurePhrasing.spokenCompensation(1.0 / 3) == "plus one third of a stop")
        #expect(ExposurePhrasing.spokenCompensation(-2.0 / 3) == "minus two thirds of a stop")
        #expect(ExposurePhrasing.spokenCompensation(1) == "plus one stop")
        #expect(ExposurePhrasing.spokenCompensation(4.0 / 3) == "plus one stop and one third")
        #expect(ExposurePhrasing.spokenCompensation(-2) == "minus 2 stops")
    }

    @Test("The uncertainty is spoken, not printed as a symbol")
    func exposureValue() {
        #expect(ExposurePhrasing.spokenExposureValue(14.1, sigmaEV: 0.5) == "EV 14.1, plus or minus 0.5")
    }

    @Test("The zone sentence names units, and infinity by name")
    func zone() {
        #expect(
            ExposurePhrasing.spokenZoneSentence(markMetres: 3, near: 1.9, far: 7.2)
                == "set the scale to 3 metres, sharp from 1.9 to 7.2 metres"
        )
        #expect(
            ExposurePhrasing.spokenZoneSentence(markMetres: 1, near: 1.4, far: .infinity)
                == "set the scale to 1 metre, sharp from 1.4 metres to infinity"
        )
    }

    @Test("A sun below the horizon is said to be below it")
    func conditions() {
        #expect(
            ExposurePhrasing.spokenConditions(sunElevationDegrees: 14.7, cloudCover: 0.2)
                == "sun 14.7 degrees above the horizon, 20 percent cloud"
        )
        #expect(
            ExposurePhrasing.spokenConditions(sunElevationDegrees: -4.2, cloudCover: nil)
                == "sun 4.2 degrees below the horizon, no weather, clear sky assumed"
        )
    }
}
