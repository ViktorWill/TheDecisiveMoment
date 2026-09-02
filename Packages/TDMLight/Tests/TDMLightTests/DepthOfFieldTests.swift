import Foundation
import Testing
@testable import TDMLight

/// Typical Leica M glass, as engraved.
enum TestGear {
    static let m6 = CameraBodyProfile(
        name: "M6",
        shutterSpeeds: [1, 1.0 / 2, 1.0 / 4, 1.0 / 8, 1.0 / 15, 1.0 / 30, 1.0 / 60, 1.0 / 125, 1.0 / 250, 1.0 / 500, 1.0 / 1000],
        iso: .fixed(400)
    )

    static let m10 = CameraBodyProfile(
        name: "M10",
        shutterSpeeds: [1, 1.0 / 2, 1.0 / 4, 1.0 / 8, 1.0 / 15, 1.0 / 30, 1.0 / 60, 1.0 / 125, 1.0 / 250, 1.0 / 500, 1.0 / 1000, 1.0 / 2000, 1.0 / 4000],
        iso: .range(minimum: 100, maximum: 6400)
    )

    static let summicron35 = LensProfile(
        name: "Summicron 35mm f/2",
        focalLengthMillimetres: 35,
        apertures: [2, 2.8, 4, 5.6, 8, 11, 16],
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    static let summicron50 = LensProfile(
        name: "Summicron 50mm f/2",
        focalLengthMillimetres: 50,
        apertures: [2, 2.8, 4, 5.6, 8, 11, 16],
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )
}

@Suite("Depth of field — EXPOSURE-MODEL §6")
struct DepthOfFieldTests {
    struct HyperfocalRow: Sendable, CustomStringConvertible {
        let focal: Double
        let aperture: Double
        let hyperfocal: Double
        var description: String { "\(Int(focal))mm f/\(aperture)" }
    }

    static let hyperfocalRows: [HyperfocalRow] = [
        HyperfocalRow(focal: 28, aperture: 4, hyperfocal: 6.56),
        HyperfocalRow(focal: 28, aperture: 5.6, hyperfocal: 4.69),
        HyperfocalRow(focal: 28, aperture: 8, hyperfocal: 3.29),
        HyperfocalRow(focal: 28, aperture: 11, hyperfocal: 2.40),
        HyperfocalRow(focal: 28, aperture: 16, hyperfocal: 1.66),
        HyperfocalRow(focal: 35, aperture: 4, hyperfocal: 10.24),
        HyperfocalRow(focal: 35, aperture: 5.6, hyperfocal: 7.33),
        HyperfocalRow(focal: 35, aperture: 8, hyperfocal: 5.14),
        HyperfocalRow(focal: 35, aperture: 11, hyperfocal: 3.75),
        HyperfocalRow(focal: 35, aperture: 16, hyperfocal: 2.59),
        HyperfocalRow(focal: 50, aperture: 4, hyperfocal: 20.88),
        HyperfocalRow(focal: 50, aperture: 5.6, hyperfocal: 14.93),
        HyperfocalRow(focal: 50, aperture: 8, hyperfocal: 10.47),
        HyperfocalRow(focal: 50, aperture: 11, hyperfocal: 7.63),
        HyperfocalRow(focal: 50, aperture: 16, hyperfocal: 5.26),
    ]

    @Test("Every hyperfocal vector", arguments: hyperfocalRows)
    func hyperfocal(_ row: HyperfocalRow) {
        let H = DepthOfField.hyperfocalMetres(focalLengthMillimetres: row.focal, aperture: row.aperture)
        #expect(abs(H - row.hyperfocal) <= 0.02, "\(row)")
    }

    struct ZoneRow: Sendable, CustomStringConvertible {
        let focal: Double
        let aperture: Double
        let focus: Double
        let near: Double
        let far: Double
        var description: String { "\(Int(focal))mm f/\(aperture) at \(focus) m" }
    }

    static let zoneRows: [ZoneRow] = [
        ZoneRow(focal: 35, aperture: 8, focus: 3, near: 1.90, far: 7.16),
        ZoneRow(focal: 35, aperture: 8, focus: 5, near: 2.53, far: 183.4),
        ZoneRow(focal: 35, aperture: 11, focus: 2, near: 1.31, far: 4.25),
        ZoneRow(focal: 50, aperture: 8, focus: 3, near: 2.34, far: 4.19),
        ZoneRow(focal: 50, aperture: 5.6, focus: 5, near: 3.75, far: 7.49),
        ZoneRow(focal: 28, aperture: 8, focus: 2, near: 1.25, far: 5.05),
    ]

    @Test("Every zone range vector", arguments: zoneRows)
    func zone(_ row: ZoneRow) {
        let range = DepthOfField.range(
            focalLengthMillimetres: row.focal,
            aperture: row.aperture,
            focusDistanceMetres: row.focus
        )
        #expect(abs(range.nearMetres - row.near) <= 0.01, "\(row) near")
        // The far limit is reported to a tenth of a metre once past ~100 m.
        #expect(abs(range.farMetres - row.far) <= max(0.01, row.far * 0.001), "\(row) far")
        #expect(!range.reachesInfinity)
    }

    @Test("Just under the hyperfocal the far limit explodes but stays finite")
    func farLimitJustUnderHyperfocal() {
        // 35 mm f/8 focused at 5 m, hyperfocal 5.14 m.
        let range = DepthOfField.range(focalLengthMillimetres: 35, aperture: 8, focusDistanceMetres: 5)
        #expect(!range.reachesInfinity)
        #expect(range.farMetres > 150 && range.farMetres < 220)
    }

    @Test("At or beyond the hyperfocal the far limit is infinity")
    func infinityBranch() {
        let hyperfocal = DepthOfField.hyperfocalMetres(focalLengthMillimetres: 35, aperture: 8)
        let atH = DepthOfField.range(focalLengthMillimetres: 35, aperture: 8, focusDistanceMetres: hyperfocal)
        #expect(atH.reachesInfinity)
        // Focused at the hyperfocal, the near limit is half of it.
        #expect(abs(atH.nearMetres - hyperfocal / 2) <= 0.02)

        let atInfinity = DepthOfField.range(focalLengthMillimetres: 35, aperture: 8, focusDistanceMetres: .infinity)
        #expect(atInfinity.reachesInfinity)
        #expect(abs(atInfinity.nearMetres - hyperfocal) < 1e-9)
    }

    @Test("A stricter circle of confusion pushes the hyperfocal further out")
    func stricterCircleOfConfusion() {
        let standard = DepthOfField.hyperfocalMetres(focalLengthMillimetres: 50, aperture: 8)
        let strict = DepthOfField.hyperfocalMetres(
            focalLengthMillimetres: 50,
            aperture: 8,
            circleOfConfusionMillimetres: 0.025
        )
        #expect(strict > standard)
        #expect(abs(strict - 12.55) <= 0.02)
    }
}

@Suite("Zone focus snapping — EXPOSURE-MODEL §6")
struct ZoneFocusTests {
    @Test("Mark plus aperture gives the sharp range")
    func markAndApertureToRange() {
        let range = ZoneFocus.range(
            lens: TestGear.summicron35,
            body: TestGear.m6,
            markMetres: 3,
            aperture: 8
        )
        #expect(abs(range.nearMetres - 1.90) <= 0.01)
        #expect(abs(range.farMetres - 7.16) <= 0.01)
    }

    @Test("The hyperfocal mark is the nearest engraved mark that still reaches infinity")
    func hyperfocalMark() {
        // 35 mm f/16: hyperfocal 2.59 m, so the 3 m mark is the one to set.
        #expect(ZoneFocus.hyperfocalMark(lens: TestGear.summicron35, body: TestGear.m6, aperture: 16) == 3.0)
        // f/8: hyperfocal 5.14 m — the 5 m mark falls just short, so 10 m it is.
        #expect(ZoneFocus.hyperfocalMark(lens: TestGear.summicron35, body: TestGear.m6, aperture: 8) == 10.0)
    }

    @Test("A desired range resolves to a mark and the widest aperture that covers it")
    func desiredRangeToSetting() throws {
        let setting = try #require(
            ZoneFocus.setting(covering: 2...6, lens: TestGear.summicron35, body: TestGear.m6)
        )
        #expect(setting.range.covers(2...6))
        #expect(TestGear.summicron35.distanceMarksMetres.contains(setting.markMetres))
        // Anything wider than the chosen aperture must fail to cover the range
        // at every engraved mark — that is what "widest that works" means.
        for aperture in TestGear.summicron35.apertures where aperture < setting.aperture {
            for mark in TestGear.summicron35.distanceMarksMetres {
                let range = ZoneFocus.range(
                    lens: TestGear.summicron35,
                    body: TestGear.m6,
                    markMetres: mark,
                    aperture: aperture
                )
                #expect(!range.covers(2...6))
            }
        }
    }

    @Test("An impossible range has no answer rather than an invented one")
    func impossibleRange() {
        // 50 mm cannot hold 0.7 m to infinity at any aperture it has.
        #expect(ZoneFocus.setting(covering: 0.7...Double.infinity, lens: TestGear.summicron50, body: TestGear.m6) == nil)
    }

    @Test("Snapping picks an engraved mark, never an interpolated distance")
    func nearestMark() {
        #expect(ZoneFocus.nearestMark(to: 2.4, on: TestGear.summicron35) == 2.0)
        #expect(ZoneFocus.nearestMark(to: 2.6, on: TestGear.summicron35) == 3.0)
        #expect(ZoneFocus.nearestMark(to: 0.5, on: TestGear.summicron35) == 0.7)
        #expect(ZoneFocus.nearestMark(to: .infinity, on: TestGear.summicron35) == .infinity)
    }
}
