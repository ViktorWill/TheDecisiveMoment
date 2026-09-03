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
        1.0 / 8_000, 1.0 / 4_000, 1.0 / 2_000, 1.0 / 1_000, 1.0 / 500, 1.0 / 250, 1.0 / 125,
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
    //
    // Every M from the M6 forward, `docs/SPEC-light.md` "The body roster". The
    // ladders and ISO ranges are the manuals' figures: the advisor is exactly as
    // accurate as this table, and a wrong top shutter speed produces confident
    // nonsense.
    //
    // The slow end is the engraved 15, 30 and 60 s rather than 16, 32 and 64 —
    // an M7's AE runs steplessly to 32 s, but 30 s is the mark on the dial and
    // marks are what the app tells the user to set.

    /// The default roll: HP5 400 at box speed.
    public static var defaultRoll: LoadedRoll {
        LoadedRoll(stock: FilmStock.stock(id: "hp5") ?? FilmStock.unnamed(boxSpeed: 400))
    }

    /// Leica M6: mechanical, 1 s–1/1000, and whatever roll is loaded.
    ///
    /// The roll carries its own medium, so the solver's latitude and bias follow
    /// the film rather than a constant, `docs/EXPOSURE-MODEL.md` §7a.
    public static func m6(
        roll: LoadedRoll = defaultRoll,
        loadedFilm: String? = nil
    ) -> CameraBody {
        mechanicalFilmBody(name: "Leica M6", roll: roll, hasMeter: true, loadedFilm: loadedFilm)
    }

    /// Leica MP: the M6 again, built to last longer. Same dial, same meter.
    public static func mp(
        roll: LoadedRoll = defaultRoll,
        loadedFilm: String? = nil
    ) -> CameraBody {
        mechanicalFilmBody(name: "Leica MP", roll: roll, hasMeter: true, loadedFilm: loadedFilm)
    }

    /// Leica M-A: 1 s–1/1000, and **no meter at all**.
    ///
    /// This is the body the app matters most to. With no meter in the camera the
    /// phone's live meter stops being a cross-check and becomes the only meter
    /// in the bag, `docs/EXPOSURE-MODEL.md` §8 — so the UI promotes it, and no
    /// copy anywhere may offer to compare against a reading that does not exist.
    public static func mA(
        roll: LoadedRoll = defaultRoll,
        loadedFilm: String? = nil
    ) -> CameraBody {
        mechanicalFilmBody(name: "Leica M-A", roll: roll, hasMeter: false, loadedFilm: loadedFilm)
    }

    /// Leica M7: 30 s–1/1000 under aperture priority, TTL meter, and 1/60 and
    /// 1/125 mechanically once the battery is flat.
    ///
    /// The AE shutter is stepless, which is why aperture priority is a strategy
    /// rather than a badge: the ±1/3 stop quantisation of a doubling dial does
    /// not apply, and the answer is an aperture and a compensation setting.
    public static func m7(
        roll: LoadedRoll = defaultRoll,
        loadedFilm: String? = nil
    ) -> CameraBody {
        CameraBody(
            name: "Leica M7",
            shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 1_000),
            // Worth knowing before the battery dies rather than after.
            mechanicalFallbackShutterSpeeds: [1.0 / 125, 1.0 / 60],
            iso: .fixed(roll),
            hasMeter: true,
            supportsAperturePriority: true,
            loadedFilm: loadedFilm
        )
    }

    /// Leica M8: 30 s–1/8000, ISO 160–2500, and **not full frame**.
    ///
    /// APS-H at 27 × 18 mm, so the circle of confusion is 0.0225 mm and every
    /// hyperfocal runs 1.333× longer than the same lens on any other M in this
    /// list. A 35 mm frames like a 47 mm, which is worth showing and changes no
    /// exposure maths.
    public static let m8 = CameraBody(
        name: "Leica M8",
        shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 8_000),
        // Two generations behind the M10: a dim side street at EV 3.0 wants ISO
        // 6250 and this sensor has not got it, §7d.
        iso: .range(minimum: 160, maximum: 2_500),
        format: .apsH,
        hasMeter: true
    )

    /// Leica M9: 30 s–1/4000, ISO 80 (pull) – 2500, full frame.
    public static let m9 = CameraBody(
        name: "Leica M9",
        shutterSpeeds: shutterLadder(slowestSeconds: 30, fastestFraction: 4_000),
        iso: .range(minimum: 80, maximum: 2_500),
        hasMeter: true
    )

    /// Leica M10: 8 s–1/4000, ISO 100–50000.
    public static let m10 = CameraBody(
        name: "Leica M10",
        shutterSpeeds: shutterLadder(slowestSeconds: 8, fastestFraction: 4_000),
        // The ceiling is the photographer's, not the sensor's: 6400 is where
        // the mockup starts and where an M10 file stops being pleasant.
        iso: .range(minimum: 100, maximum: 50_000, ceiling: 6_400),
        hasMeter: true
    )

    /// Leica M11: 60 s–1/4000 on the mechanical shutter, 1/8000 and 1/16000 on
    /// the electronic one, ISO 64–50000.
    ///
    /// The electronic speeds are kept apart from the dial because they are a
    /// mode the photographer has to switch into — but they are carried, because
    /// f/2 in bright sun is reachable on this ladder and on no other M,
    /// including this body's own mechanical shutter, §7b.
    public static let m11 = CameraBody(
        name: "Leica M11",
        shutterSpeeds: shutterLadder(slowestSeconds: 60, fastestFraction: 4_000),
        electronicShutterSpeeds: [1.0 / 16_000, 1.0 / 8_000],
        iso: .range(minimum: 64, maximum: 50_000, ceiling: 6_400),
        hasMeter: true
    )

    /// A fully mechanical film M: the whole dial keeps working with no battery,
    /// because there is nothing in the shutter for a battery to do.
    private static func mechanicalFilmBody(
        name: String,
        roll: LoadedRoll,
        hasMeter: Bool,
        loadedFilm: String?
    ) -> CameraBody {
        let ladder = shutterLadder(slowestSeconds: 1, fastestFraction: 1_000)
        return CameraBody(
            name: name,
            shutterSpeeds: ladder,
            mechanicalFallbackShutterSpeeds: ladder,
            iso: .fixed(roll),
            hasMeter: hasMeter,
            loadedFilm: loadedFilm
        )
    }

    /// The bodies seeded on first launch: film first, then digital, oldest to
    /// newest inside each — the order of `design/Bodies.dc.html`.
    public static var bodies: [CameraBody] { [m6(), m7(), mp(), mA(), m8, m9, m10, m11] }

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
