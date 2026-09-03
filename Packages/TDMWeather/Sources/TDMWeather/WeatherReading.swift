import Foundation
import TDMLight

/// Weather as the light model wants it: an observation, or an honest admission
/// that there is none.
///
/// `cloudCover` is `nil` in the fallback case, which is exactly what
/// `LightConditions` needs to widen σ by 0.7 EV in quadrature (§9).
public struct WeatherReading: Sendable, Equatable {
    /// The instant this reading describes.
    public let date: Date
    /// The observation, or `nil` when the model has fallen back to clear sky.
    public let observation: WeatherObservation?
    public let freshness: WeatherFreshness
    /// Why there is no observation, when there is none. Surfaced so the UI can
    /// say *"no weather"* rather than silently guessing.
    public let failure: WeatherProviderError?

    public init(
        date: Date,
        observation: WeatherObservation?,
        freshness: WeatherFreshness,
        failure: WeatherProviderError? = nil
    ) {
        self.date = date
        self.observation = observation
        self.freshness = freshness
        self.failure = failure
    }

    /// A reading with no weather behind it at all.
    public static func clearSkyFallback(at date: Date, failure: WeatherProviderError? = nil) -> WeatherReading {
        WeatherReading(date: date, observation: nil, freshness: .unavailable, failure: failure)
    }

    /// `nil` when the clear-sky fallback is in force.
    public var cloudCover: Double? { observation?.cloudCover }

    public var precipitation: Precipitation { observation?.precipitation ?? .none }

    public var usesClearSkyFallback: Bool { observation == nil }

    public var isStale: Bool { freshness == .stale }
}
