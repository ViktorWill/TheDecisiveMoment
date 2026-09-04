import Foundation
import Testing
import TDMCore
@testable import TDMPersistence

@Suite("Seed gear catalogue")
struct GearCatalogueTests {
    @Test("The roster is every M from the M6 forward, film then digital")
    func seedsTheWholeRoster() {
        #expect(
            GearCatalogue.bodies.map(\.name) == [
                "Leica M6", "Leica M7", "Leica MP", "Leica M-A",
                "Leica M8", "Leica M9", "Leica M10", "Leica M11"
            ]
        )
        #expect(GearCatalogue.bodies.allSatisfy { $0.isValid })
    }

    @Test("The M-A has no meter, and it is the only body in the roster without one")
    func onlyTheMAHasNoMeter() {
        #expect(!GearCatalogue.mA().hasMeter)
        #expect(GearCatalogue.bodies.filter { !$0.hasMeter }.map(\.name) == ["Leica M-A"])
    }

    @Test("The M7 has aperture priority, and nothing else does")
    func onlyTheM7HasAperturePriority() {
        #expect(GearCatalogue.bodies.filter(\.supportsAperturePriority).map(\.name) == ["Leica M7"])
        // A flat battery leaves 1/60 and 1/125 mechanically, and nothing else.
        #expect(GearCatalogue.m7().mechanicalFallbackShutterSpeeds.sorted() == [1.0 / 125, 1.0 / 60])
        // A fully mechanical M loses nothing at all.
        #expect(GearCatalogue.mp().mechanicalFallbackShutterSpeeds == GearCatalogue.mp().sortedShutterSpeeds)
        // A digital body with a flat battery is a paperweight.
        #expect(GearCatalogue.m10.mechanicalFallbackShutterSpeeds.isEmpty)
    }

    @Test("The M8 is APS-H, and it is the only body in the roster that is not full frame")
    func onlyTheM8IsCropped() {
        #expect(GearCatalogue.m8.format == .apsH)
        #expect(abs(GearCatalogue.m8.circleOfConfusionMillimetres - 0.0225) < 0.0001)
        #expect(GearCatalogue.bodies.filter { !$0.format.isFullFrame }.map(\.name) == ["Leica M8"])
        #expect(GearCatalogue.bodies.filter(\.format.isFullFrame).allSatisfy {
            abs($0.circleOfConfusionMillimetres - 0.030) < 0.0001
        })
        // 30 s – 1/8000, the fastest mechanical shutter of the roster.
        #expect(GearCatalogue.m8.sortedShutterSpeeds.first == 1.0 / 8_000)
        #expect(GearCatalogue.m8.iso.availableValues.first == 160)
    }

    @Test("Only the M11 has an electronic shutter, and it reaches 1/16000")
    func onlyTheM11HasAnElectronicShutter() {
        #expect(GearCatalogue.bodies.filter(\.hasElectronicShutter).map(\.name) == ["Leica M11"])
        // Kept off the dial: it is a mode the photographer has to switch into.
        #expect(GearCatalogue.m11.fastestShutter == 1.0 / 4_000)
        #expect(GearCatalogue.m11.fastestShutterInAnyMode == 1.0 / 16_000)
    }

    @Test("The M8 and M9 top out two generations behind the M10")
    func theOlderSensorsRunOut() {
        #expect(GearCatalogue.m8.iso.availableValues.last ?? 0 < 2_500)
        #expect(GearCatalogue.m9.iso.availableValues.last ?? 0 < 2_500)
        #expect(GearCatalogue.m9.iso.availableValues.first == 80)
        #expect(GearCatalogue.m10.iso.availableValues.last ?? 0 > 6_400)
    }

    @Test("The M6 is a film body: one fixed roll speed, 1 s to 1/1000")
    func m6IsFilm() {
        let m6 = GearCatalogue.m6()
        #expect(m6.iso.isFilm)
        #expect(m6.iso.availableValues == [400])
        #expect(m6.sortedShutterSpeeds.first == 1.0 / 1_000)
        #expect(m6.sortedShutterSpeeds.last == 1)
        // The roll, not a free-text name, is what the solver reads, §7a.
        #expect(m6.loadedRoll?.stock.id == "hp5")
        #expect(m6.medium == .blackAndWhiteNegative)
    }

    @Test("Digital bodies carry their real ladders and ISO ceilings")
    func digitalBodies() {
        #expect(GearCatalogue.m10.sortedShutterSpeeds.first == 1.0 / 4_000)
        #expect(GearCatalogue.m10.sortedShutterSpeeds.last == 8)
        #expect(GearCatalogue.m10.iso.availableValues.first == 100)
        // The ceiling is the photographer's preference, and it is stored.
        #expect(GearCatalogue.m10.iso.ceiling == 6_400)
        #expect(GearCatalogue.m10.iso.solvableValues.last == 6_400)

        #expect(GearCatalogue.m11.sortedShutterSpeeds.first == 1.0 / 4_000)
        #expect(GearCatalogue.m11.sortedShutterSpeeds.last == 60)
        #expect(GearCatalogue.m11.iso.availableValues.first == 64)

        // Both stop at 50000 — the ladder is enumerated in full stops from the
        // floor, so the top rung is the last one at or below the ceiling.
        #expect(GearCatalogue.m10.iso.availableValues.last == 25_600)
        #expect(GearCatalogue.m11.iso.availableValues.last == 32_768)
    }

    @Test("The shutter dial has the engraved slow speeds, not a doubling series")
    func shutterDialUsesEngravedSlowSpeeds() {
        let slow = GearCatalogue.shutterDial.filter { $0 >= 1 }
        #expect(slow == [1, 2, 4, 8, 15, 30, 60])
        #expect(!slow.contains(16))
        #expect(!slow.contains(64))
    }

    @Test("Eight lenses, 21 to 90 mm — two of them 35 mm")
    func seedsEightLenses() {
        #expect(GearCatalogue.lenses.map(\.focalLengthMillimetres) == [21, 24, 28, 35, 35, 50, 75, 90])
        #expect(GearCatalogue.lenses.allSatisfy { $0.isValid })
    }

    @Test("The Summilux and Summicron 35s differ only in speed, not in scale")
    func theTwo35sShareAScale() {
        #expect(GearCatalogue.summilux35.sortedApertures.first == 1.4)
        #expect(GearCatalogue.summilux35.sortedApertures.last == 16.0)
        #expect(GearCatalogue.summilux35.sortedDistanceMarks == GearCatalogue.summicron35.sortedDistanceMarks)
        #expect(GearCatalogue.summilux35.minimumFocusMetres == 0.7)
    }

    @Test("Every lens has an infinity mark and ascending finite marks")
    func marksAreWellFormed() {
        for lens in GearCatalogue.lenses {
            let marks = lens.sortedDistanceMarks
            #expect(marks.contains { !$0.isFinite }, "\(lens.name) has no ∞ mark")
            let finite = marks.filter(\.isFinite)
            #expect(finite == finite.sorted())
            #expect(Set(finite).count == finite.count, "\(lens.name) repeats a mark")
            #expect(finite.first == lens.minimumFocusMetres, "\(lens.name) starts off its minimum focus")
        }
    }

    @Test("The 90 mm scale starts at 1 m, because the barrel does")
    func ninetyStartsAtOneMetre() {
        #expect(GearCatalogue.elmarit90.minimumFocusMetres == 1.0)
        #expect(!GearCatalogue.elmarit90.sortedDistanceMarks.contains(0.7))
    }

    @Test("Marks stop at the last one engraved before infinity")
    func wideLensesStopAtFiveMetres() {
        // The 21 and 24 run 0.7 m to 5 m and then ∞; the 28 and longer carry a
        // 10 m mark as well. Inventing the missing one would be honesty rule 4.
        #expect(GearCatalogue.superElmar21.sortedDistanceMarks.filter(\.isFinite).last == 5.0)
        #expect(GearCatalogue.elmarit24.sortedDistanceMarks.filter(\.isFinite).last == 5.0)
        #expect(GearCatalogue.elmarit28.sortedDistanceMarks.filter(\.isFinite).last == 10.0)
    }

    @Test("Aperture rings click in half stops between the engraved numbers")
    func apertureClicksAreHalfStops() {
        #expect(GearCatalogue.summicron35.sortedApertures.first == 2.0)
        #expect(GearCatalogue.summicron35.sortedApertures.last == 16.0)
        #expect(GearCatalogue.summicron35.sortedApertures.contains(6.7))
        #expect(GearCatalogue.superElmar21.sortedApertures.first == 3.4)
        #expect(GearCatalogue.elmarit90.sortedApertures.first == 2.8)

        // Half a stop apart means a factor of 2^(1/4) in f-number. The printed
        // numbers are the traditional rounded ones — f/6.7 rather than 6.727,
        // f/13 rather than 13.45 — so each gap is only half a stop to about a
        // tenth of a stop, which is well inside σ.
        let stops = GearCatalogue.summicron35.sortedApertures
        for (lower, upper) in zip(stops, stops.dropFirst()) {
            let stopsApart = 2 * log2(upper / lower)
            #expect(abs(stopsApart - 0.5) < 0.12, "f/\(lower) to f/\(upper) is \(stopsApart) stops")
        }
    }

    @Test("Seeded profiles pair a real body with a real lens")
    func profilesReferenceSeededGear() {
        let bodyNames = Set(GearCatalogue.bodies.map(\.name))
        let lensNames = Set(GearCatalogue.lenses.map(\.name))
        #expect(GearCatalogue.profiles.count == 3)
        for profile in GearCatalogue.profiles {
            #expect(profile.isValid)
            #expect(bodyNames.contains(profile.body.name))
            #expect(lensNames.contains(profile.lens.name))
        }
    }
}

@Suite("Calibration offsets")
struct CalibrationOffsetTests {
    @Test("Scene and light source together identify an offset")
    func identityCoversLightSource() {
        let day = CalibrationOffset(sceneIdentifier: "shadedSideOfStreet", isArtificialLight: false, offsetEV: -0.4)
        let night = CalibrationOffset(sceneIdentifier: "shadedSideOfStreet", isArtificialLight: true, offsetEV: -0.4)
        #expect(day.id != night.id)
    }

    @Test("An implausible offset is a mis-measurement, not a calibration")
    func rejectsImplausibleOffsets() {
        #expect(CalibrationOffset(sceneIdentifier: "openSky", isArtificialLight: false, offsetEV: 0.7).isPlausible)
        #expect(!CalibrationOffset(sceneIdentifier: "openSky", isArtificialLight: false, offsetEV: -6).isPlausible)
        #expect(!CalibrationOffset(sceneIdentifier: "openSky", isArtificialLight: false, offsetEV: .nan).isPlausible)
    }
}
