import Foundation
import Testing
import TDMCore
@testable import TDMPersistence

@Suite("Seed gear catalogue")
struct GearCatalogueTests {
    @Test("The three seeded bodies are the ones the spec names")
    func seedsThreeBodies() {
        #expect(GearCatalogue.bodies.map(\.name) == ["Leica M6", "Leica M10", "Leica M11"])
        #expect(GearCatalogue.bodies.allSatisfy { $0.isValid })
    }

    @Test("The M6 is a film body: one fixed roll speed, 1 s to 1/1000")
    func m6IsFilm() {
        let m6 = GearCatalogue.m6(loadedFilmISO: 400)
        #expect(m6.iso.isFilm)
        #expect(m6.iso.availableValues == [400])
        #expect(m6.sortedShutterSpeeds.first == 1.0 / 1_000)
        #expect(m6.sortedShutterSpeeds.last == 1)
        #expect(m6.loadedFilm != nil)
    }

    @Test("Digital bodies carry their real ladders and ISO ceilings")
    func digitalBodies() {
        #expect(GearCatalogue.m10.sortedShutterSpeeds.first == 1.0 / 4_000)
        #expect(GearCatalogue.m10.sortedShutterSpeeds.last == 8)
        #expect(GearCatalogue.m10.iso.availableValues.first == 100)

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

    @Test("Seven lenses, 21 to 90 mm")
    func seedsSevenLenses() {
        #expect(GearCatalogue.lenses.map(\.focalLengthMillimetres) == [21, 24, 28, 35, 50, 75, 90])
        #expect(GearCatalogue.lenses.allSatisfy { $0.isValid })
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
