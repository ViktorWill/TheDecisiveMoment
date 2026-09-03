// Not compiled at all in the Free configuration: a free Apple ID cannot carry
// com.apple.developer.weatherkit, so importing the framework would link it and
// every call would come back `.notAuthorised`. `docs/SPEC-light.md`, "Sky, when
// there is no WeatherKit".
#if canImport(WeatherKit) && !TDM_NO_WEATHERKIT
import CoreLocation
import Foundation
import TDMCore
import WeatherKit

/// The real provider. Thin by design — `docs/ARCHITECTURE.md` says this layer is
/// verified by reading, and the tests run against `StubWeatherProvider`.
///
/// This is the only network call the app makes at runtime, and it is cached for
/// ~15 minutes by ``WeatherService``.
public struct WeatherKitProvider: WeatherProvider {
    public init() {}

    public func current(at coordinate: Coordinate) async throws -> WeatherObservation {
        let location = Self.location(coordinate)
        do {
            let current = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .current
            )
            return WeatherObservation(
                date: current.date,
                cloudCover: current.cloudCover,
                condition: Self.skyCondition(current.condition),
                precipitationIntensityMillimetresPerHour:
                    current.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
                visibilityMetres: current.visibility.converted(to: .meters).value
            )
        } catch {
            throw Self.mapped(error, coordinate: coordinate)
        }
    }

    public func hourly(
        at coordinate: Coordinate,
        from start: Date,
        through end: Date
    ) async throws -> [WeatherObservation] {
        guard end >= start else { return [] }
        let location = Self.location(coordinate)
        do {
            let forecast = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .hourly(startDate: start, endDate: end)
            )
            guard !forecast.forecast.isEmpty else {
                throw WeatherProviderError.noDataForLocation(coordinate)
            }
            return forecast.forecast.map { hour in
                WeatherObservation(
                    date: hour.date,
                    cloudCover: hour.cloudCover,
                    condition: Self.skyCondition(hour.condition),
                    precipitationIntensityMillimetresPerHour:
                        hour.precipitationAmount.converted(to: .millimeters).value,
                    visibilityMetres: hour.visibility.converted(to: .meters).value
                )
            }
        } catch {
            throw Self.mapped(error, coordinate: coordinate)
        }
    }

    // MARK: - Mapping

    private static func location(_ coordinate: Coordinate) -> CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// WeatherKit's condition vocabulary, reduced to what the model consumes.
    ///
    /// The enum is not frozen, so unknown cases fall back to the cloud cover
    /// alone rather than to a guess about precipitation.
    static func skyCondition(_ condition: WeatherKit.WeatherCondition) -> SkyCondition {
        switch condition {
        case .clear, .mostlyClear, .hot, .frigid, .windy, .breezy:
            return .clear
        case .partlyCloudy, .mostlyCloudy:
            return .partlyCloudy
        case .cloudy:
            return .cloudy
        case .foggy, .haze, .smoky, .blowingDust:
            return .fog
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain, .hail,
             .tropicalStorm, .hurricane:
            return .rain
        case .snow, .heavySnow, .flurries, .sleet, .blizzard, .blowingSnow, .wintryMix, .sunFlurries:
            return .snow
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorm
        @unknown default:
            return .partlyCloudy
        }
    }

    static func mapped(_ error: any Error, coordinate: Coordinate) -> WeatherProviderError {
        if let error = error as? WeatherProviderError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .dataNotAllowed, .internationalRoamingOff:
                return .unreachable
            default:
                return .underlying(urlError.localizedDescription)
            }
        }
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .permissionDenied:
                return .notAuthorised
            default:
                return .underlying(String(describing: weatherError))
            }
        }
        return .underlying(String(describing: error))
    }
}
#endif
