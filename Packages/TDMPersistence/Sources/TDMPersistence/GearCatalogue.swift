import Foundation
import TDMCore

/// The gear the app ships with, seeded on first launch.
///
/// The engraved distance marks are the point of this file. The whole output of
/// the Light screen is *"set the barrel to this mark"*, so a mark a lens does
/// not have makes the advice unusable — see `docs/SPEC-light.md`, which carries
/// the same tables and is the source of truth for them.
///
/// Distances are metres, focal lengths and the circle of confusion millimetres,
/// shutter speeds `TimeInterval` in seconds.
public enum GearCatalogue {
    // MARK: - Ladders

    /// The conventional f-number ladder in half stops.
    ///
    /// Modern M glass clicks in half stops, so these are settings the user can
    /// physically reach; the printed numbers are the traditional rounded ones
    /// (f/6.7, not f/6.727) because that is what the ring is marked against.
    public static let halfStopApertures: [Double] = [
        1.0, 1.2, 1.4, 1.7, 2.0, 2.4, 2.8, 3.4, 4.0, 4.8, 5.6, 6.7, 8.0, 9.5, 11.0, 13.0, 16.0, 19.0, 22.0
    ]

    /// The half-stop clicks from `widest` to `narrowest`, inclusive.
    ///
    /// - Precondition: both bounds appear in ``halfStopApertures``.
    public static func apertures(from widest: Double, to narrowest: Double) -> [Double] {
        halfStopApertures.filter { $0 >= widest - 1e-9 && $0 <= narrowest + 1e-9 }
    }

    /// The speeds engraved on a Leica shutter dial, seconds, ascending.
    ///
    /// The slow end is 15, 30 and 60 seconds rather than 16, 32 and 64: the dial
    /// says so, and a doubling series would invent settings the camera has not
    /// got.
    public static let shutterDial: [TimeInterval] = [
        1.0 / 4_000, 1.0 / 2_000, 1.0 / 1_000, 1.0 / 500, 1.0 / 250, 1.0 / 125,
        1.0 / 60, 1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4, 1.0 / 2,
        1, 2, 4, 8, 15, 30, 60
    ]

    /// The dial's speeds from `1/fastest` up to `slowest` seconds, inclusive.
    /// `1/250`, never `250`.
    public static func shutterLadder(slowestSeconds slowest: Double, fastestFraction fastest: Int) -> [TimeInterval] {
        let quickest = 1.0 / Double(fastest)
        return shutterDial.filter { $0 >= quickest - 1e-12 && $0 <= slowest + 1e-12 }
    }

    // MARK: - Bodies

    /// Leica M6: mechanical, 1 s–1/1000, and whatever roll is loaded.
    public static func m6(loadedFilmISO: Int = 400, loadedFilm: String? = "Kodak Tri-X 400") -> CameraBody {
        CameraBody(
            name: "Leica M6",
            shutterSpeeds: shutterLadder(slowestSeconds: 1, fastestFraction: 1_000),
            iso: .fixed(loadedFilmISO),
            hasMeter: true,
            loadedFilm: loadedFilm
        )
    }

    /// Leica M10: 8 s–1/4000, ISO 100–50000.
    public static let m10 = CameraBody(
        name: "Leica M10",
        shutterSpeeds: shutterLadder(slowestSeconds: 8, fastestFraction: 4_000),
        iso: .range(minimum: 100, maximum: 50_000),
        hasMeter: true
    )

    /// Leica M11: 60 s–1/4000 on the mechanical shutter, ISO 64–50000.
    ///
    /// The electronic shutter goes to 1/16000, but it is not what this camera is
    /// used with on the street and the app would be recommending a mode the
    /// photographer has to remember to switch into.
    public static let m11 = CameraBody(
        name: "Leica M11",
        shutterSpeeds: shutterLadder(slowestSeconds: 60, fastestFraction: 4_000),
        iso: .range(minimum: 64, maximum: 50_000),
        hasMeter: true
    )

    /// The bodies seeded on first launch.
    public static var bodies: [CameraBody] { [m6(), m10, m11] }

    // MARK: - Lenses

    /// The lenses seeded on first launch, wide to long.
    ///
    /// Marks as engraved on the barrel; `∞` is engraved on every one of them and
    /// travels as `.infinity`.
    public static var lenses: [Lens] { [superElmar21, elmarit24, elmarit28, summicron35, summicron50, apoSummicron75, elmarit90] }

    /// Super-Elmar-M 21 mm f/3.4 ASPH.
    public static let superElmar21 = Lens(
        name: "Super-Elmar-M 21mm f/3.4",
        focalLengthMillimetres: 21,
        apertures: apertures(from: 3.4, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// Elmarit-M 24 mm f/2.8 ASPH.
    public static let elmarit24 = Lens(
        name: "Elmarit-M 24mm f/2.8",
        focalLengthMillimetres: 24,
        apertures: apertures(from: 2.8, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// Elmarit-M 28 mm f/2.8 ASPH.
    public static let elmarit28 = Lens(
        name: "Elmarit-M 28mm f/2.8",
        focalLengthMillimetres: 28,
        apertures: apertures(from: 2.8, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// Summicron-M 35 mm f/2 ASPH — the reference lens of `EXPOSURE-MODEL.md` §6.
    public static let summicron35 = Lens(
        name: "Summicron-M 35mm f/2",
        focalLengthMillimetres: 35,
        apertures: apertures(from: 2, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// Summicron-M 50 mm f/2.
    public static let summicron50 = Lens(
        name: "Summicron-M 50mm f/2",
        focalLengthMillimetres: 50,
        apertures: apertures(from: 2, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// APO-Summicron-M 75 mm f/2 ASPH.
    public static let apoSummicron75 = Lens(
        name: "APO-Summicron-M 75mm f/2",
        focalLengthMillimetres: 75,
        apertures: apertures(from: 2, to: 16),
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    /// Elmarit-M 90 mm f/2.8. Focuses no closer than 1 m, and the scale starts
    /// there — the shorter lenses' 0.7 m mark does not exist on this barrel.
    public static let elmarit90 = Lens(
        name: "Elmarit-M 90mm f/2.8",
        focalLengthMillimetres: 90,
        apertures: apertures(from: 2.8, to: 16),
        distanceMarksMetres: [1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 1.0
    )

    // MARK: - Profiles

    /// The profiles seeded on first launch. The first one is selected.
    ///
    /// One profile per body with the lens most likely to be on it; the user can
    /// build others from the seeded bodies and lenses.
    public static var profiles: [GearProfile] {
        [
            GearProfile(name: "M6 · 35mm", body: m6(), lens: summicron35),
            GearProfile(name: "M10 · 35mm", body: m10, lens: summicron35),
            GearProfile(name: "M11 · 50mm", body: m11, lens: summicron50)
        ]
    }
}
