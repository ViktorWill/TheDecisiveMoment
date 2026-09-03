import Foundation
import Synchronization
import Testing
import TDMCore
import TDMLight
@testable import TDMWeather

/// A provider that counts calls, so the cache can be shown to work rather than
/// assumed to.
private final class CountingProvider: WeatherProvider, Sendable {
    /// Call counts and the scripted failure, behind a `Mutex` so the type is
    /// genuinely `Sendable` rather than asserted to be.
    private struct State {
        var currentCalls = 0
        var hourlyCalls = 0
        var failure: WeatherProviderError?
    }

    private let state: Mutex<State>
    private let observation: WeatherObservation

    init(observation: WeatherObservation, failure: WeatherProviderError? = nil) {
        self.observation = observation
        self.state = Mutex(State(failure: failure))
    }

    var currentCalls: Int { state.withLock { $0.currentCalls } }
    var hourlyCalls: Int { state.withLock { $0.hourlyCalls } }

    func startFailing(_ failure: WeatherProviderError) {
        state.withLock { $0.failure = failure }
    }

    func current(at coordinate: Coordinate) async throws -> WeatherObservation {
        let failure: WeatherProviderError? = state.withLock {
            $0.currentCalls += 1
            return $0.failure
        }
        if let failure { throw failure }
        return observation
    }

    func hourly(
        at coordinate: Coordinate,
        from start: Date,
        through end: Date
    ) async throws -> [WeatherObservation] {
        let failure: WeatherProviderError? = state.withLock {
            $0.hourlyCalls += 1
            return $0.failure
        }
        if let failure { throw failure }
        let hour: TimeInterval = 3_600
        let count = max(0, Int((end.timeIntervalSince(start) / hour).rounded(.down)) + 1)
        return (0..<count).map {
            WeatherObservation(
                date: start.addingTimeInterval(Double($0) * hour),
                cloudCover: observation.cloudCover,
                condition: observation.condition
            )
        }
    }
}

/// A clock the tests move by hand; nothing here waits on wall time.
private final class TestClock: Sendable {
    private let now: Mutex<Date>

    init(_ start: Date) { now = Mutex(start) }

    func advance(by interval: TimeInterval) {
        now.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    /// `WeatherService` wants a synchronous clock, which is why this is a mutex
    /// rather than an actor.
    var date: @Sendable () -> Date {
        { [self] in now.withLock { $0 } }
    }
}

private let manhattan = Coordinate(latitude: 40.7580, longitude: -73.9850)
private let start = Date(timeIntervalSince1970: 1_781_000_000)

@Suite("Weather observations")
struct WeatherObservationTests {
    @Test("Cloud cover is clamped to 0…1")
    func clampsCloudCover() {
        #expect(WeatherObservation(date: start, cloudCover: 1.4).cloudCover == 1)
        #expect(WeatherObservation(date: start, cloudCover: -0.2).cloudCover == 0)
    }

    @Test("Precipitation buckets follow the 2.5 mm/h boundary")
    func bucketsPrecipitation() {
        func observation(_ intensity: Double) -> WeatherObservation {
            WeatherObservation(
                date: start,
                cloudCover: 0.5,
                condition: .rain,
                precipitationIntensityMillimetresPerHour: intensity
            )
        }
        #expect(observation(0).precipitation == .none)
        #expect(observation(0.4).precipitation == .light)
        #expect(observation(6).precipitation == .heavy)
    }

    @Test("Thick fog costs light even with no rain falling")
    func treatsThickFogAsLightPrecipitation() {
        let fog = WeatherObservation(date: start, cloudCover: 0.9, condition: .fog, visibilityMetres: 400)
        #expect(fog.precipitation == .light)

        let haze = WeatherObservation(date: start, cloudCover: 0.9, condition: .fog, visibilityMetres: 8_000)
        #expect(haze.precipitation == .none)
    }
}

@Suite("Weather service")
struct WeatherServiceTests {
    @Test("A reading inside the TTL comes from the cache")
    func cachesWithinTimeToLive() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let clock = TestClock(start)
        let service = WeatherService(provider: provider, clock: clock.date)

        _ = await service.reading(at: manhattan)
        clock.advance(by: 10 * 60)
        let second = await service.reading(at: manhattan)

        #expect(provider.currentCalls == 1)
        #expect(second.freshness == .fresh)
        #expect(second.cloudCover == 0.2)
    }

    @Test("Past the TTL the provider is asked again")
    func refetchesAfterTimeToLive() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let clock = TestClock(start)
        let service = WeatherService(provider: provider, clock: clock.date)

        _ = await service.reading(at: manhattan)
        clock.advance(by: 16 * 60)
        _ = await service.reading(at: manhattan)

        #expect(provider.currentCalls == 2)
    }

    @Test("Pull-to-refresh bypasses the cache")
    func refreshBypassesCache() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let service = WeatherService(provider: provider, clock: TestClock(start).date)

        _ = await service.reading(at: manhattan)
        _ = await service.refreshedReading(at: manhattan)

        #expect(provider.currentCalls == 2)
    }

    @Test("A failed refresh keeps a usable cached observation, marked stale")
    func fallsBackToStaleCache() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let clock = TestClock(start)
        let service = WeatherService(provider: provider, clock: clock.date)

        _ = await service.reading(at: manhattan)
        provider.startFailing(.unreachable)
        clock.advance(by: 20 * 60)
        let reading = await service.reading(at: manhattan)

        #expect(reading.freshness == .stale)
        #expect(reading.cloudCover == 0.2)
        #expect(reading.failure == .unreachable)
        #expect(!reading.usesClearSkyFallback)
    }

    @Test("Beyond the useful age the cache is dropped for the clear-sky fallback")
    func dropsExpiredCache() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let clock = TestClock(start)
        let service = WeatherService(provider: provider, clock: clock.date)

        _ = await service.reading(at: manhattan)
        provider.startFailing(.unreachable)
        clock.advance(by: 4 * 60 * 60)
        let reading = await service.reading(at: manhattan)

        #expect(reading.usesClearSkyFallback)
        #expect(reading.freshness == .unavailable)
        #expect(reading.cloudCover == nil)
    }

    @Test("Failure with nothing cached is not fatal: clear sky, and it says so")
    func failsSoftly() async {
        let service = WeatherService(provider: StubWeatherProvider.offline, clock: TestClock(start).date)
        let reading = await service.reading(at: manhattan)

        #expect(reading.usesClearSkyFallback)
        #expect(reading.failure == .unreachable)
        #expect(reading.precipitation == .none)
    }

    @Test("The fallback reading widens σ by 0.7 EV in quadrature")
    func fallbackWidensUncertainty() async {
        let service = WeatherService(provider: StubWeatherProvider.offline, clock: TestClock(start).date)
        let reading = await service.reading(at: manhattan)

        let withWeather = LightModel.estimate(LightConditions(sunElevationDegrees: 30, cloudCover: 0.2))
        let without = LightModel.estimate(
            LightConditions(
                sunElevationDegrees: 30,
                cloudCover: reading.cloudCover,
                weatherFreshness: reading.freshness
            )
        )

        // Without weather the estimate loses the "cloud cover known" term as
        // well as taking the 0.7 EV fallback penalty, so σ goes 0.5 → 0.8 ⊕ 0.7.
        #expect(abs(withWeather.sigmaEV - 0.5) < 1e-9)
        #expect(abs(without.sigmaEV - (0.8 * 0.8 + 0.7 * 0.7).squareRoot()) < 1e-9)
    }

    @Test("Hourly readings cover every requested hour, in order")
    func hourlyCoversEveryHour() async {
        let provider = CountingProvider(observation: StubWeatherProvider.brightAfternoon)
        let service = WeatherService(provider: provider, clock: TestClock(start).date)
        let end = start.addingTimeInterval(11 * 3_600)

        let readings = await service.hourlyReadings(at: manhattan, from: start, through: end)

        #expect(readings.count == 12)
        #expect(readings.allSatisfy { !$0.usesClearSkyFallback })
        #expect(readings.map(\.date) == readings.map(\.date).sorted())
    }

    @Test("Hours the forecast does not reach fall back rather than interpolate")
    func hourlyFallsBackForUncoveredHours() async {
        let provider = StubWeatherProvider(forecastHours: 4)
        let service = WeatherService(provider: provider, clock: TestClock(start).date)
        let end = start.addingTimeInterval(11 * 3_600)

        let readings = await service.hourlyReadings(at: manhattan, from: start, through: end)

        #expect(readings.count == 12)
        #expect(readings.prefix(4).allSatisfy { !$0.usesClearSkyFallback })
        #expect(readings.dropFirst(4).allSatisfy { $0.usesClearSkyFallback })
    }

    @Test("A failed hourly fetch yields a full set of fallback readings")
    func hourlyFailsSoftly() async {
        let service = WeatherService(provider: StubWeatherProvider.offline, clock: TestClock(start).date)
        let readings = await service.hourlyReadings(
            at: manhattan,
            from: start,
            through: start.addingTimeInterval(11 * 3_600)
        )

        #expect(readings.count == 12)
        #expect(readings.allSatisfy { $0.usesClearSkyFallback })
        #expect(readings.allSatisfy { $0.failure == .unreachable })
    }

    @Test("Coordinates within about 100 m share a cache entry")
    func roundsCacheKey() {
        let key = WeatherService.CacheKey(manhattan)
        let nearby = WeatherService.CacheKey(Coordinate(latitude: 40.75803, longitude: -73.98474))
        let elsewhere = WeatherService.CacheKey(Coordinate(latitude: 40.7700, longitude: -73.9850))

        #expect(key == nearby)
        #expect(key != elsewhere)
    }
}
