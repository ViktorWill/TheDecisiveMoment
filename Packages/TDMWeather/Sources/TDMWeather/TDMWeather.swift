import Foundation
import TDMCore
import TDMLight

/// Namespace for the weather layer.
///
/// The `WeatherProvider` protocol and its `WeatherKitProvider`,
/// `ManualWeatherProvider` and `StubWeatherProvider` implementations live here.
/// WeatherKit is the only network call the app makes at runtime, and a build
/// signed with a free Apple ID does not make it: `ManualWeatherProvider` is the
/// only provider there.
public enum TDMWeather {
    /// How long a fetched observation stays usable before it is refetched.
    public static let cacheTimeToLive: TimeInterval = 15 * 60

    /// Whether this build has WeatherKit compiled into it.
    ///
    /// `false` under `TDM_NO_WEATHERKIT`, the Free configuration. Wiring reads
    /// this rather than repeating the compilation condition at every call site.
    public static var hasWeatherKit: Bool {
        #if canImport(WeatherKit) && !TDM_NO_WEATHERKIT
        true
        #else
        false
        #endif
    }
}
