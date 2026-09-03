import Foundation
import TDMCore
import TDMLight

/// A provider with a cache in front of it, and a promise never to throw.
///
/// The screen must not block on the network: a rough number in the field beats
/// a spinner. Every method here answers immediately with the best thing it has —
/// a fresh observation, a stale one, or the clear-sky fallback — and says which.
public actor WeatherService {
    /// How long an observation counts as current.
    public static let timeToLive: TimeInterval = TDMWeather.cacheTimeToLive
    /// Past this age a cached observation is not worth keeping, even as stale
    /// input; three hours of drift is beyond what `stale` claims.
    public static let maximumUsefulAge: TimeInterval = 3 * 60 * 60
    /// An hourly sample further than this from the hour it is asked to describe
    /// is not that hour's weather.
    static let hourlyMatchTolerance: TimeInterval = 45 * 60

    private let provider: any WeatherProvider
    private let timeToLive: TimeInterval
    private let maximumUsefulAge: TimeInterval
    private let clock: @Sendable () -> Date

    private var currentCache: [CacheKey: CachedObservation] = [:]
    private var hourlyCache: [CacheKey: CachedForecast] = [:]

    public init(
        provider: any WeatherProvider,
        timeToLive: TimeInterval = WeatherService.timeToLive,
        maximumUsefulAge: TimeInterval = WeatherService.maximumUsefulAge,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.timeToLive = timeToLive
        self.maximumUsefulAge = maximumUsefulAge
        self.clock = clock
    }

    /// Conditions now, from the cache when it is current and from the provider
    /// when it is not. Never throws.
    public func reading(at coordinate: Coordinate) async -> WeatherReading {
        await reading(at: coordinate, ignoringCache: false)
    }

    /// The same, but always asks the provider first. This is pull-to-refresh.
    public func refreshedReading(at coordinate: Coordinate) async -> WeatherReading {
        await reading(at: coordinate, ignoringCache: true)
    }

    /// One reading per hour from `start` through `end`, in order.
    ///
    /// Hours the forecast does not cover come back as the clear-sky fallback
    /// rather than as an interpolation of the hours around them: the scrubber
    /// then widens the uncertainty for exactly those hours.
    public func hourlyReadings(
        at coordinate: Coordinate,
        from start: Date,
        through end: Date
    ) async -> [WeatherReading] {
        let hours = Self.hours(from: start, through: end)
        guard !hours.isEmpty else { return [] }

        let key = CacheKey(coordinate)
        let now = clock()
        var forecast = hourlyCache[key]
        var failure: WeatherProviderError?

        let covers = forecast.map { $0.covers(hours, tolerance: Self.hourlyMatchTolerance) } ?? false
        if forecast == nil || now.timeIntervalSince(forecast!.fetched) >= timeToLive || !covers {
            do {
                let observations = try await provider.hourly(at: coordinate, from: start, through: end)
                forecast = CachedForecast(fetched: now, observations: observations)
                hourlyCache[key] = forecast
            } catch {
                failure = Self.providerError(error)
            }
        }

        guard let forecast else {
            return hours.map { WeatherReading.clearSkyFallback(at: $0, failure: failure) }
        }
        let age = now.timeIntervalSince(forecast.fetched)
        guard age <= maximumUsefulAge else {
            return hours.map { WeatherReading.clearSkyFallback(at: $0, failure: failure) }
        }
        let freshness: WeatherFreshness = age < timeToLive ? .fresh : .stale

        return hours.map { hour in
            guard let match = forecast.observation(for: hour, tolerance: Self.hourlyMatchTolerance) else {
                return WeatherReading.clearSkyFallback(at: hour, failure: failure)
            }
            return WeatherReading(date: hour, observation: match, freshness: freshness, failure: failure)
        }
    }

    /// Forget everything cached. Used when the user picks a different city.
    public func clearCache() {
        currentCache.removeAll()
        hourlyCache.removeAll()
    }

    // MARK: - Current

    private func reading(at coordinate: Coordinate, ignoringCache: Bool) async -> WeatherReading {
        let key = CacheKey(coordinate)
        let now = clock()

        if !ignoringCache,
           let cached = currentCache[key],
           now.timeIntervalSince(cached.fetched) < timeToLive {
            return WeatherReading(date: now, observation: cached.observation, freshness: .fresh)
        }

        do {
            let observation = try await provider.current(at: coordinate)
            currentCache[key] = CachedObservation(fetched: now, observation: observation)
            return WeatherReading(date: now, observation: observation, freshness: .fresh)
        } catch {
            let failure = Self.providerError(error)
            // A cached observation within the useful age is still better input
            // than clear sky — but it is reported as stale, which costs σ.
            if let cached = currentCache[key],
               now.timeIntervalSince(cached.fetched) <= maximumUsefulAge {
                return WeatherReading(
                    date: now,
                    observation: cached.observation,
                    freshness: .stale,
                    failure: failure
                )
            }
            return .clearSkyFallback(at: now, failure: failure)
        }
    }

    // MARK: - Support

    static func providerError(_ error: any Error) -> WeatherProviderError {
        (error as? WeatherProviderError) ?? .underlying(String(describing: error))
    }

    /// The hours from `start` through `end`, each snapped to the top of its hour.
    static func hours(from start: Date, through end: Date) -> [Date] {
        guard end >= start else { return [] }
        let hour: TimeInterval = 3_600
        let first = (start.timeIntervalSinceReferenceDate / hour).rounded(.down) * hour
        var dates: [Date] = []
        var t = first
        while t <= end.timeIntervalSinceReferenceDate + 1 {
            dates.append(Date(timeIntervalSinceReferenceDate: t))
            t += hour
        }
        return dates
    }

    /// Cache key: the coordinate to three decimals, about 100 m.
    ///
    /// Weather does not change over a city block, and rounding stops a walking
    /// user from refetching with every location update.
    struct CacheKey: Hashable {
        let latitude: Int
        let longitude: Int

        init(_ coordinate: Coordinate) {
            latitude = Int((coordinate.latitude * 1_000).rounded())
            longitude = Int((coordinate.longitude * 1_000).rounded())
        }
    }

    struct CachedObservation {
        let fetched: Date
        let observation: WeatherObservation
    }

    struct CachedForecast {
        let fetched: Date
        let observations: [WeatherObservation]

        func observation(for date: Date, tolerance: TimeInterval) -> WeatherObservation? {
            observations
                .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                .flatMap { abs($0.date.timeIntervalSince(date)) <= tolerance ? $0 : nil }
        }

        func covers(_ hours: [Date], tolerance: TimeInterval) -> Bool {
            hours.allSatisfy { observation(for: $0, tolerance: tolerance) != nil }
        }
    }
}
