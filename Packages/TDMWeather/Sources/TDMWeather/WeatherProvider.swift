import Foundation
import TDMCore

/// Where weather comes from.
///
/// The protocol exposes only what the light model consumes — cloud cover,
/// condition, precipitation intensity, visibility — so a second provider can be
/// added later without touching a caller.
public protocol WeatherProvider: Sendable {
    /// Conditions now, at a coordinate.
    func current(at coordinate: Coordinate) async throws -> WeatherObservation

    /// Hourly samples from `start` up to and including `end`.
    ///
    /// May return fewer hours than asked for; the caller widens its uncertainty
    /// for the hours it did not get rather than inventing them.
    func hourly(at coordinate: Coordinate, from start: Date, through end: Date) async throws -> [WeatherObservation]
}

/// Why a weather fetch failed.
///
/// None of these are fatal: the caller falls back to clear sky and says so.
public enum WeatherProviderError: Error, Equatable, Sendable {
    /// The device is offline, or the request timed out.
    case unreachable
    /// The service answered, but not for this place or time.
    case noDataForLocation(Coordinate)
    /// The service refused the request — a missing entitlement, usually.
    case notAuthorised
    /// Anything else, kept as text because the caller can only surface it.
    case underlying(String)
}
