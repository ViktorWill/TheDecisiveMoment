import SwiftUI
import TDMLight

/// Where the sun is and what it is about to do.
///
/// Golden and blue hour are the two facts that change when you leave the café,
/// so they are countdowns rather than clock times — with the clock time beside
/// them for planning.
struct SunPanelView: View {
    let sun: SolarPosition
    let events: SolarEvents?
    let now: Date
    /// The bearing of the street at a selected spot, degrees. When present, the
    /// panel says which side of it is lit.
    let streetBearingDegrees: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                reading("Elevation", value: format(sun.elevationDegrees) + "°")
                reading("Azimuth", value: format(sun.azimuthDegrees) + "°")
                reading("Compass", value: compassPoint(sun.azimuthDegrees))
            }

            if let next = nextEvents.first {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(nextEvents, id: \.label) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(event.colour)
                                .frame(width: 7, height: 7)
                            Text(event.label)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(LightTheme.primaryText)
                            Text(ExposurePhrasing.countdown(event.date.timeIntervalSince(now)))
                                .font(.system(size: 14, design: .rounded).monospacedDigit())
                                .foregroundStyle(LightTheme.secondaryText)
                            Spacer(minLength: 4)
                            Text(event.date, format: .dateTime.hour().minute())
                                .font(.system(size: 14, design: .rounded).monospacedDigit())
                                .foregroundStyle(LightTheme.secondaryText)
                        }
                    }
                }
                .accessibilityHint("Next light events at this location")
                .id(next.label)
            }

            if let litSide {
                Text(litSide)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LightTheme.accent)
            }
        }
        .panel("Sun")
    }

    private func reading(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(LightTheme.labelFont)
                .foregroundStyle(LightTheme.secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(LightTheme.primaryText)
        }
    }

    private struct Event {
        let label: String
        let date: Date
        let colour: Color
    }

    /// The next few thresholds, soonest first. Events already past are dropped
    /// rather than shown as negative countdowns.
    private var nextEvents: [Event] {
        guard let events else { return [] }
        let all: [Event?] = [
            events.morningGoldenHour.map { Event(label: "Golden hour", date: $0.start, colour: LightTheme.golden) },
            events.eveningGoldenHour.map { Event(label: "Golden hour", date: $0.start, colour: LightTheme.golden) },
            events.eveningBlueHour.map { Event(label: "Blue hour", date: $0.start, colour: LightTheme.blue) },
            events.morningBlueHour.map { Event(label: "Blue hour", date: $0.start, colour: LightTheme.blue) },
            events.sunset.map { Event(label: "Sunset", date: $0, colour: LightTheme.caution) },
            events.sunrise.map { Event(label: "Sunrise", date: $0, colour: LightTheme.caution) }
        ]
        return all
            .compactMap { $0 }
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(3)
            .map { $0 }
    }

    /// Which façade is lit, from the street's bearing and the sun's azimuth.
    /// The wording is shared with the Map's *light right now* strip.
    private var litSide: String? {
        SolarPhrasing.litSideSentence(
            streetBearingDegrees: streetBearingDegrees,
            sunAzimuthDegrees: sun.azimuthDegrees,
            sunElevationDegrees: sun.elevationDegrees
        )
    }

    private func format(_ degrees: Double) -> String {
        SolarPhrasing.degrees(degrees)
    }

    private func compassPoint(_ azimuthDegrees: Double) -> String {
        SolarPhrasing.compassPoint(azimuthDegrees)
    }
}
