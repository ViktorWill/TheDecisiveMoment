import Foundation
import TDMLight

/// The sky, coarsely — only what the light model can actually use.
///
/// WeatherKit reports far more than this. Anything the model does not consume
/// stays out, so a second provider can be written against a small surface.
public enum SkyCondition: String, Sendable, CaseIterable, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case snow
    case thunderstorm

    /// Fog, rain and snow cost light beyond what cloud cover alone accounts for.
    public var isObscured: Bool {
        switch self {
        case .clear, .partlyCloudy, .cloudy: false
        case .fog, .rain, .snow, .thunderstorm: true
        }
    }
}

/// One weather sample: current conditions, or one hour of the forecast.
public struct WeatherObservation: Sendable, Equatable, Codable {
    /// The instant this sample describes.
    public var date: Date
    /// Fraction of the sky covered, `0…1`. Feeds `Modifiers.cloudDeltaEV`.
    public var cloudCover: Double
    public var condition: SkyCondition
    /// Precipitation intensity in millimetres per hour, as WeatherKit reports it.
    public var precipitationIntensityMillimetresPerHour: Double
    /// Horizontal visibility in metres.
    public var visibilityMetres: Double

    public init(
        date: Date,
        cloudCover: Double,
        condition: SkyCondition = .clear,
        precipitationIntensityMillimetresPerHour: Double = 0,
        visibilityMetres: Double = 20_000
    ) {
        self.date = date
        self.cloudCover = min(max(cloudCover, 0), 1)
        self.condition = condition
        self.precipitationIntensityMillimetresPerHour = max(0, precipitationIntensityMillimetresPerHour)
        self.visibilityMetres = max(0, visibilityMetres)
    }

    /// The model's precipitation bucket, `docs/EXPOSURE-MODEL.md` §4b.
    ///
    /// The 2.5 mm/h threshold is the conventional meteorological boundary
    /// between light and moderate rain; heavy fog costs about as much light as
    /// light rain, so it lands in the same bucket rather than being ignored.
    public var precipitation: Precipitation {
        if precipitationIntensityMillimetresPerHour >= 2.5 { return .heavy }
        if precipitationIntensityMillimetresPerHour > 0 { return .light }
        if condition == .fog, visibilityMetres < 1_000 { return .light }
        return .none
    }
}
