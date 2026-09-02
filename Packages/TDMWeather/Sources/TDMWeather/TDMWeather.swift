import Foundation
import TDMCore
import TDMLight

/// Namespace for the weather layer.
///
/// The `WeatherProvider` protocol and its `WeatherKitProvider` and
/// `StubWeatherProvider` implementations land here in M3. WeatherKit is the
/// only network call the app makes at runtime.
public enum TDMWeather {
    /// How long a fetched observation stays usable before it is refetched.
    public static let cacheTimeToLive: TimeInterval = 15 * 60
}
