import Foundation
import Synchronization
import TDMCore
import TDMLight

/// The sky as the person holding the phone sees it.
///
/// Five segments, and the cover values are lifted straight from the
/// `docs/EXPOSURE-MODEL.md` §4b table by way of `docs/SPEC-light.md`, "Sky,
/// when there is no WeatherKit". They are not to be re-derived: the whole point
/// is that a manual reading lands on exactly the rows the model already has.
///
/// | Segment | Cover | Δ EV |
/// |---|---|---|
/// | Clear | 0.00 | −0.00 |
/// | Light haze | 0.25 | −0.28 |
/// | Hazy sun | 0.50 | −0.92 |
/// | Cloudy bright | 0.75 | −1.84 |
/// | Overcast | 1.00 | −3.00 |
public enum SkySegment: String, Sendable, CaseIterable, Codable, Identifiable {
    case clear
    case lightHaze
    case hazySun
    case cloudyBright
    case overcast

    public var id: String { rawValue }

    /// Fraction of the sky covered, `0…1` — the §4b row this segment *is*.
    public var cloudCover: Double {
        switch self {
        case .clear: 0.00
        case .lightHaze: 0.25
        case .hazySun: 0.50
        case .cloudyBright: 0.75
        case .overcast: 1.00
        }
    }

    /// What the model takes off clear sky for this segment, in stops.
    ///
    /// Computed from ``Modifiers/cloudDeltaEV(cover:)`` rather than tabulated,
    /// so this can never drift from the maths it is supposed to name.
    public var deltaEV: Double { Modifiers.cloudDeltaEV(cover: cloudCover) }

    /// The condition the segment implies. Only cloud cover reaches the model;
    /// this exists so a manual observation is a whole ``WeatherObservation``
    /// rather than a half-built one.
    public var condition: SkyCondition {
        switch self {
        case .clear, .lightHaze: .clear
        case .hazySun: .partlyCloudy
        case .cloudyBright, .overcast: .cloudy
        }
    }

    /// The segment nearest a measured cover, for opening the override on what
    /// the forecast already says rather than on `Clear`.
    public static func nearest(cover: Double) -> SkySegment {
        allCases.min { abs($0.cloudCover - cover) < abs($1.cloudCover - cover) } ?? .clear
    }
}

/// The sky, from the photographer instead of from the network.
///
/// This is the only provider in a build signed with a free Apple ID: WeatherKit
/// needs a paid membership, and a call that is guaranteed to come back
/// ``WeatherProviderError/notAuthorised`` is worse than no call at all.
///
/// It makes no network request, ever. `hourly` holds the observed cover across
/// the whole window — the sun position the scrubber draws is computed on
/// device and is real, and ``WeatherService`` widens σ for the hours ahead
/// (`docs/EXPOSURE-MODEL.md` §9) rather than dropping the feature.
public final class ManualWeatherProvider: WeatherProvider, Sendable {
    /// The segment the user last chose, behind a `Mutex` so the type is
    /// genuinely `Sendable`: the UI writes it, the service reads it.
    private let state: Mutex<SkySegment>
    private let clock: @Sendable () -> Date

    public init(segment: SkySegment = .clear, clock: @escaping @Sendable () -> Date = Date.init) {
        self.state = Mutex(segment)
        self.clock = clock
    }

    public var segment: SkySegment { state.withLock { $0 } }

    public func setSegment(_ segment: SkySegment) {
        state.withLock { $0 = segment }
    }

    /// Not a forecast: one observation, held constant. ``WeatherService`` reads
    /// this to decide what the hours ahead are worth.
    public var providesForecast: Bool { false }

    public func current(at coordinate: Coordinate) async throws -> WeatherObservation {
        observation(at: clock())
    }

    public func hourly(
        at coordinate: Coordinate,
        from start: Date,
        through end: Date
    ) async throws -> [WeatherObservation] {
        guard end >= start else { return [] }
        let hour: TimeInterval = 3_600
        let count = Int((end.timeIntervalSince(start) / hour).rounded(.down)) + 1
        return (0..<count).map { observation(at: start.addingTimeInterval(Double($0) * hour)) }
    }

    private func observation(at date: Date) -> WeatherObservation {
        let segment = self.segment
        return WeatherObservation(
            date: date,
            cloudCover: segment.cloudCover,
            condition: segment.condition
        )
    }
}
