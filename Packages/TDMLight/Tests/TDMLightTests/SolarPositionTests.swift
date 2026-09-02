import Foundation
import Testing
@testable import TDMLight

@Suite("Solar position — EXPOSURE-MODEL §1")
struct SolarPositionTests {
    struct Vector: Sendable, CustomStringConvertible {
        var description: String { name }
        let name: String
        let date: Date
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let azimuth: Double
    }

    static let vectors: [Vector] = [
        Vector(name: "NYC, summer solstice, 12:00 EDT", date: utc(2026, 6, 21, 16), latitude: 40.7308, longitude: -73.9973, elevation: 68.876, azimuth: 219.468),
        Vector(name: "NYC, winter solstice, 12:00 EST", date: utc(2026, 12, 21, 17), latitude: 40.7308, longitude: -73.9973, elevation: 25.850, azimuth: 178.514),
        Vector(name: "NYC, summer solstice, 19:00 EDT", date: utc(2026, 6, 21, 23), latitude: 40.7308, longitude: -73.9973, elevation: 14.727, azimuth: 71.507),
        Vector(name: "Tokyo, equinox, 12:00 JST", date: utc(2026, 3, 20, 3), latitude: 35.6762, longitude: 139.6503, elevation: 54.052, azimuth: 175.289),
        Vector(name: "Berlin, 12:00 CEST", date: utc(2026, 9, 2, 10), latitude: 52.52, longitude: 13.405, elevation: 43.335, azimuth: 202.789),
    ]

    @Test("Every solar position vector", arguments: vectors)
    func vector(_ vector: Vector) {
        let position = Solar.position(
            date: vector.date,
            latitudeDegrees: vector.latitude,
            longitudeDegrees: vector.longitude
        )
        #expect(abs(position.elevationDegrees - vector.elevation) <= 0.05, "\(vector.name) elevation")
        #expect(abs(position.azimuthDegrees - vector.azimuth) <= 0.2, "\(vector.name) azimuth")
    }

    @Test("Winter solstice noon elevation matches 90 − latitude − obliquity")
    func winterSolsticeIndependentCheck() {
        let position = Solar.position(
            date: utc(2026, 12, 21, 17),
            latitudeDegrees: 40.7308,
            longitudeDegrees: -73.9973
        )
        // 17:00 UTC is four minutes off solar noon in New York, so the two
        // figures agree to a few hundredths of a degree rather than exactly.
        let independent = 90 - 40.7308 - 23.438
        #expect(abs(position.elevationDegrees - independent) <= 0.05)
        #expect(abs(position.declinationDegrees - (-23.438)) <= 0.01)
    }

    @Test("Julian day matches the J2000.0 epoch")
    func julianDayEpoch() {
        #expect(abs(Solar.julianDay(utc(2000, 1, 1, 12)) - 2_451_545.0) < 1e-6)
        #expect(abs(Solar.julianDay(utc(1970, 1, 1)) - 2_440_587.5) < 1e-6)
    }

    @Test("Refraction lifts a sun on the horizon and vanishes near the zenith")
    func refractionBranches() {
        #expect(Solar.refractionDegrees(geometricElevationDegrees: 88) == 0)
        #expect(abs(Solar.refractionDegrees(geometricElevationDegrees: 45) - 0.0161) < 0.001)
        #expect(abs(Solar.refractionDegrees(geometricElevationDegrees: 0) - 0.4819) < 0.001)
        // Below −0.575° the fit reverses sign but stays small.
        #expect(Solar.refractionDegrees(geometricElevationDegrees: -5) > 0)
    }
}

@Suite("Solar events — EXPOSURE-MODEL §1, by bisection")
struct SolarEventsTests {
    // Berlin, early September: a day with an unambiguous sunrise and sunset.
    let latitude = 52.52
    let longitude = 13.405
    var dayStart: Date { utc(2026, 9, 2) }

    @Test("Sunrise and sunset bracket the day and land on the horizon")
    func sunriseAndSunset() throws {
        let events = Solar.events(
            dayStartingAt: dayStart,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude
        )
        let sunrise = try #require(events.sunrise)
        let sunset = try #require(events.sunset)
        #expect(sunrise < sunset)
        for event in [sunrise, sunset] {
            let h = Solar.elevationDegrees(
                date: event,
                latitudeDegrees: latitude,
                longitudeDegrees: longitude
            )
            #expect(abs(h) < 0.01)
        }
        // Sunrise in Berlin on 2 September is a little after 04:30 UTC.
        #expect(abs(sunrise.timeIntervalSince(dayStart) - 4.5 * 3600) < 3600)
    }

    @Test("Golden hour runs from +6° to −4° and brackets sunset")
    func eveningGoldenHour() throws {
        let events = Solar.events(
            dayStartingAt: dayStart,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude
        )
        let golden = try #require(events.eveningGoldenHour)
        let sunset = try #require(events.sunset)
        #expect(golden.contains(sunset))
        #expect(golden.duration > 0)
        let start = Solar.elevationDegrees(date: golden.start, latitudeDegrees: latitude, longitudeDegrees: longitude)
        let end = Solar.elevationDegrees(date: golden.end, latitudeDegrees: latitude, longitudeDegrees: longitude)
        #expect(abs(start - 6) < 0.01)
        #expect(abs(end + 4) < 0.01)
    }

    @Test("Blue hour runs from −4° to −6° and follows golden hour")
    func eveningBlueHour() throws {
        let events = Solar.events(
            dayStartingAt: dayStart,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude
        )
        let golden = try #require(events.eveningGoldenHour)
        let blue = try #require(events.eveningBlueHour)
        #expect(blue.start == golden.end)
        let end = Solar.elevationDegrees(date: blue.end, latitudeDegrees: latitude, longitudeDegrees: longitude)
        #expect(abs(end + 6) < 0.01)
    }

    @Test("Morning windows precede the evening ones")
    func morningWindows() throws {
        let events = Solar.events(
            dayStartingAt: dayStart,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude
        )
        let morningBlue = try #require(events.morningBlueHour)
        let morningGolden = try #require(events.morningGoldenHour)
        let eveningGolden = try #require(events.eveningGoldenHour)
        #expect(morningBlue.end == morningGolden.start)
        #expect(morningGolden.end < eveningGolden.start)
    }

    @Test("Polar day has no sunrise")
    func polarDay() {
        // Longyearbyen at midsummer: the sun never reaches the horizon going down.
        let events = Solar.events(dayStartingAt: utc(2026, 6, 21), latitudeDegrees: 78.22, longitudeDegrees: 15.65)
        #expect(events.sunrise == nil)
        #expect(events.sunset == nil)
    }
}
