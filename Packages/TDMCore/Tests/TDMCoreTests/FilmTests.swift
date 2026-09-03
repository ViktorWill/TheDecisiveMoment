import Foundation
import Testing
@testable import TDMCore

/// `docs/EXPOSURE-MODEL.md` §7a and the stock table in `docs/SPEC-light.md`.
@Suite("Film — medium, latitude, loaded roll")
struct FilmTests {
    @Test("The eight seeded stocks are the ones the spec lists")
    func catalogue() {
        #expect(FilmStock.catalogue.count == 8)
        #expect(Set(FilmStock.catalogue.map(\.id)).count == 8)

        let hp5 = FilmStock.stock(id: "hp5")
        #expect(hp5?.name == "Ilford HP5 Plus")
        #expect(hp5?.boxSpeed == 400)
        #expect(hp5?.medium == .blackAndWhiteNegative)

        #expect(FilmStock.stock(id: "portra400")?.medium == .colourNegative)
        #expect(FilmStock.stock(id: "velvia50")?.medium == .slide)
        #expect(FilmStock.stock(id: "velvia50")?.boxSpeed == 50)
        #expect(FilmStock.stock(id: "nothing-like-this") == nil)
    }

    @Test("Latitude and bias are properties of the medium, not of the call site")
    func mediumTable() {
        #expect(Medium.blackAndWhiteNegative.latitude.overStops == 3.0)
        #expect(Medium.blackAndWhiteNegative.latitude.underStops == 1.0)
        #expect(Medium.slide.latitude.overStops == 0.5)
        #expect(Medium.digital.latitude.underStops == 2.0)

        #expect(Medium.blackAndWhiteNegative.isFilm)
        #expect(!Medium.digital.isFilm)
        #expect(Medium.digital.biasEV < 0)
        #expect(Medium.colourNegative.biasEV > Medium.blackAndWhiteNegative.biasEV)
    }

    @Test("Over-exposure is forgiven far further than under, and only on negative")
    func asymmetry() {
        // Sign: positive error is under-exposure, §7a.
        #expect(Medium.blackAndWhiteNegative.latitude.accepts(errorStops: -2.5))
        #expect(!Medium.blackAndWhiteNegative.latitude.accepts(errorStops: 1.5))
        #expect(!Medium.slide.latitude.accepts(errorStops: -1.1))
        #expect(Medium.slide.latitude.accepts(errorStops: 0.5))
    }

    @Test("A pushed roll states its speed, its stops and its cost")
    func loadedRoll() throws {
        let hp5 = try #require(FilmStock.stock(id: "hp5"))

        let boxed = LoadedRoll(stock: hp5)
        #expect(boxed.ratedAt == 400)
        #expect(boxed.pushStops == 0)
        #expect(boxed.displayName == "HP5 400")
        #expect(boxed.cost == nil)

        let pushed = LoadedRoll(stock: hp5, ratedAt: 1_600)
        #expect(abs(pushed.pushStops - 2) < 1e-9)
        #expect(pushed.signedStops == "+2")
        #expect(pushed.displayName == "HP5 400 @ 1600 (+2)")
        #expect(pushed.cost != nil)

        let pulled = LoadedRoll(stock: hp5, ratedAt: 200)
        #expect(abs(pulled.pushStops + 1) < 1e-9)
        #expect(pulled.signedStops == "−1")
        #expect(pulled.medium == .blackAndWhiteNegative)

        // Ratings offered are whole stops around box speed, §7b.
        #expect(boxed.availableRatings == [200, 400, 800, 1_600, 3_200])
    }

    @Test("A roll with no named stock is still a roll")
    func unnamedRoll() {
        let roll = LoadedRoll(speed: 400)
        #expect(!roll.stock.isNamed)
        #expect(roll.ratedAt == 400)
        #expect(roll.pushStops == 0)
        #expect(roll.medium == .blackAndWhiteNegative)
        #expect(roll.displayName == "ISO 400")
    }

    @Test("ISOMode carries the roll on film and the ceiling on a sensor")
    func isoMode() throws {
        let film = ISOMode.fixed(LoadedRoll(stock: FilmStock.stock(id: "delta3200")!))
        #expect(film.medium == .blackAndWhiteNegative)
        #expect(film.solvableValues == [3_200])
        #expect(film.ceiling == nil)
        #expect(film.loadedRoll?.stock.name == "Ilford Delta 3200")

        let sensor = ISOMode.range(minimum: 100, maximum: 6_400, ceiling: 1_600)
        #expect(sensor.medium == .digital)
        #expect(sensor.solvableValues == [100, 200, 400, 800, 1_600])
        #expect(sensor.ceiling == 1_600)
        #expect(sensor.sensorRange?.minimum == 100)
        #expect(sensor.sensorRange?.maximum == 6_400)
        #expect(sensor.loadedRoll == nil)
    }

    @Test("A body with a loaded roll round-trips through JSON")
    func rollCoding() throws {
        let roll = LoadedRoll(stock: FilmStock.stock(id: "portra400")!, ratedAt: 800)
        let body = CameraBody(
            name: "M6",
            shutterSpeeds: [1.0 / 60, 1.0 / 125],
            iso: .fixed(roll)
        )

        let data = try JSONEncoder().encode(body)
        let decoded = try JSONDecoder().decode(CameraBody.self, from: data)
        #expect(decoded.loadedRoll == roll)
        #expect(decoded.medium == .colourNegative)
        #expect(decoded.isoDescription == "Portra 400 @ 800 (+1)")
    }

    /// A body written before the M8 joined the roster has no format, no
    /// electronic ladder and no aperture-priority flag. It must still decode,
    /// as a full-frame body with none of those things.
    @Test("A body stored before the roster grew still decodes")
    func decodesWithoutTheNewFields() throws {
        let json = """
        {
            "id": "6D9C2E0E-3A2A-4C25-9E5A-3E2F1A0B7C11",
            "name": "M6",
            "shutterSpeeds": [0.008, 0.004],
            "iso": { "mode": "fixed", "value": 400, "stock": "hp5" },
            "circleOfConfusionMillimetres": 0.03,
            "hasMeter": true
        }
        """
        let decoded = try JSONDecoder().decode(CameraBody.self, from: Data(json.utf8))
        #expect(decoded.format == .fullFrame)
        #expect(decoded.electronicShutterSpeeds.isEmpty)
        #expect(decoded.mechanicalFallbackShutterSpeeds.isEmpty)
        #expect(!decoded.supportsAperturePriority)
        #expect(abs(decoded.circleOfConfusionMillimetres - 0.030) < 1e-9)
    }
}
