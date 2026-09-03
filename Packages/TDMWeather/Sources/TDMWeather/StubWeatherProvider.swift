import Foundation
import TDMCore

/// A provider that answers from a script, for previews and tests.
///
/// Tests never touch the network; previews must work in an office with no sky
/// in sight. Both use this.
public struct StubWeatherProvider: WeatherProvider {
    /// What `current(at:)` answers, unless `failure` is set.
    public var observation: WeatherObservation
    /// How the cloud cover walks across the forecast, per hour, in `0…1`.
    public var hourlyCloudCoverDrift: Double
    /// How many hours `hourly(at:from:through:)` is willing to cover. Shorter
    /// than the request is a legitimate answer and the caller must handle it.
    public var forecastHours: Int
    /// When set, every call throws this instead of answering.
    public var failure: WeatherProviderError?

    public init(
        observation: WeatherObservation = StubWeatherProvider.brightAfternoon,
        hourlyCloudCoverDrift: Double = 0.05,
        forecastHours: Int = 12,
        failure: WeatherProviderError? = nil
    ) {
        self.observation = observation
        self.hourlyCloudCoverDrift = hourlyCloudCoverDrift
        self.forecastHours = forecastHours
        self.failure = failure
    }

    /// The worked example in `docs/EXPOSURE-MODEL.md` §4: 20 % cloud.
    public static let brightAfternoon = WeatherObservation(
        date: Date(timeIntervalSince1970: 0),
        cloudCover: 0.2,
        condition: .partlyCloudy
    )

    /// A provider that always fails, for exercising the fallback path.
    public static let offline = StubWeatherProvider(failure: .unreachable)

    public func current(at coordinate: Coordinate) async throws -> WeatherObservation {
        if let failure { throw failure }
        return observation
    }

    public func hourly(
        at coordinate: Coordinate,
        from start: Date,
        through end: Date
    ) async throws -> [WeatherObservation] {
        if let failure { throw failure }
        guard end >= start, forecastHours > 0 else { return [] }
        let hour: TimeInterval = 3_600
        let requested = Int((end.timeIntervalSince(start) / hour).rounded(.up)) + 1
        return (0..<min(requested, forecastHours)).map { index in
            WeatherObservation(
                date: start.addingTimeInterval(Double(index) * hour),
                cloudCover: observation.cloudCover + Double(index) * hourlyCloudCoverDrift,
                condition: observation.condition,
                precipitationIntensityMillimetresPerHour:
                    observation.precipitationIntensityMillimetresPerHour,
                visibilityMetres: observation.visibilityMetres
            )
        }
    }
}
