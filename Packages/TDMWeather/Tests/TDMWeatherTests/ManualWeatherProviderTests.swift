import Foundation
import Testing
import TDMCore
import TDMLight
@testable import TDMWeather

/// The five segments are the `docs/EXPOSURE-MODEL.md` §4b rows, and this is
/// what says so. If one of these numbers ever has to be edited to make the test
/// pass, the code is wrong — the table is not.
@Suite("Manual sky")
struct ManualWeatherProviderTests {
    /// Somewhere with a sky, and a fixed instant so nothing depends on when the
    /// tests run.
    static let coordinate = Coordinate(latitude: 40.7580, longitude: -73.9855)
    static let now = Date(timeIntervalSince1970: 1_781_020_800)

    @Test("The five segments are the §4b table, cover and Δ EV")
    func segmentsMatchTheModelTable() {
        let rows: [(segment: SkySegment, cover: Double, deltaEV: Double)] = [
            (.clear, 0.00, -0.00),
            (.lightHaze, 0.25, -0.28),
            (.hazySun, 0.50, -0.92),
            (.cloudyBright, 0.75, -1.84),
            (.overcast, 1.00, -3.00)
        ]
        #expect(rows.map(\.segment) == SkySegment.allCases)
        for row in rows {
            #expect(row.segment.cloudCover == row.cover)
            // The table is quoted to two decimals, so compare at that width.
            #expect(abs(row.segment.deltaEV - row.deltaEV) <= 0.005)
            #expect(abs(Modifiers.cloudDeltaEV(cover: row.segment.cloudCover) - row.deltaEV) <= 0.005)
        }
    }

    @Test("A chosen segment is what the observation carries")
    func currentObservationCarriesTheSegment() async throws {
        let provider = ManualWeatherProvider(clock: { Self.now })
        provider.setSegment(.cloudyBright)

        let observation = try await provider.current(at: Self.coordinate)

        #expect(observation.cloudCover == 0.75)
        #expect(observation.condition == .cloudy)
        #expect(observation.precipitation == .none)
        #expect(observation.date == Self.now)
    }

    @Test("A manual reading reports σ 0.5, not the stale-forecast 0.8")
    func manualReadingIsFresh() async {
        let provider = ManualWeatherProvider(segment: .hazySun, clock: { Self.now })
        let service = WeatherService(provider: provider, clock: { Self.now })

        let reading = await service.reading(at: Self.coordinate)

        #expect(reading.freshness == .fresh)
        #expect(reading.isStale == false)
        #expect(reading.cloudCover == 0.5)
        // An observation taken now is an observation, not a stale forecast, §9.
        let sigma = Uncertainty.sigmaEV(
            sunElevationDegrees: 30,
            regime: .daylight,
            weather: reading.freshness
        )
        #expect(sigma == 0.5)
        #expect(Uncertainty.sigmaEV(sunElevationDegrees: 30, regime: .daylight, weather: .stale) == 0.8)
    }

    @Test("The 12-hour window holds the cover and widens σ ahead of now")
    func hourlyHoldsCoverAndWidensAhead() async {
        let provider = ManualWeatherProvider(segment: .overcast, clock: { Self.now })
        let service = WeatherService(provider: provider, clock: { Self.now })
        let start = Date(timeIntervalSince1970: Self.now.timeIntervalSince1970 - 1_800)
        let end = start.addingTimeInterval(11 * 3_600)

        let readings = await service.hourlyReadings(at: Self.coordinate, from: start, through: end)

        #expect(readings.count == 12)
        // Held constant: the sky the user reported is the sky for the window.
        #expect(readings.allSatisfy { $0.cloudCover == 1.0 })
        #expect(readings.allSatisfy { $0.usesClearSkyFallback == false })

        // The hour the user is standing in is an observation.
        #expect(readings.filter { $0.date <= Self.now }.allSatisfy { $0.freshness == .fresh })
        // Every hour past now is an extrapolation of that one observation, so
        // §9's stale σ applies rather than the 0.5 EV of a reading taken now.
        let ahead = readings.filter { $0.date > Self.now }
        #expect(ahead.count == 10)
        #expect(ahead.allSatisfy { $0.freshness == .stale })
    }

    @Test("A forecasting provider keeps its future hours fresh")
    func forecastHoursStayFresh() async {
        let service = WeatherService(provider: StubWeatherProvider(), clock: { Self.now })
        let start = Date(timeIntervalSince1970: Self.now.timeIntervalSince1970 - 1_800)

        let readings = await service.hourlyReadings(
            at: Self.coordinate,
            from: start,
            through: start.addingTimeInterval(3 * 3_600)
        )

        #expect(readings.allSatisfy { $0.freshness == .fresh })
    }

    @Test("The nearest segment to a forecast cover opens the override on it")
    func nearestSegment() {
        #expect(SkySegment.nearest(cover: 0.0) == .clear)
        #expect(SkySegment.nearest(cover: 0.2) == .lightHaze)
        #expect(SkySegment.nearest(cover: 0.55) == .hazySun)
        #expect(SkySegment.nearest(cover: 0.8) == .cloudyBright)
        #expect(SkySegment.nearest(cover: 1.0) == .overcast)
    }

    /// The build-level assertion lives in `Scripts/assert-no-weatherkit.sh`,
    /// which builds the Free scheme and reads the linked frameworks out of the
    /// binary. This is its counterpart on the source side: under the flag the
    /// module reports no WeatherKit, and `WeatherKitProvider` is not compiled,
    /// so nothing can reference it.
    @Test("The flag and the module agree about WeatherKit")
    func flagMatchesTheModule() {
        #if TDM_NO_WEATHERKIT
        #expect(TDMWeather.hasWeatherKit == false)
        #else
        #expect(TDMWeather.hasWeatherKit == (canImportWeatherKit))
        #endif
    }

    private var canImportWeatherKit: Bool {
        #if canImport(WeatherKit)
        true
        #else
        false
        #endif
    }
}
