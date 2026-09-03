import SwiftUI
import TDMCore
import TDMLight
import TDMWeather

/// *Light right now* for one spot: the setting, where the sun is, and which
/// façade it is on (`docs/SPEC-map.md`, "Spot detail").
///
/// The whole strip is a button: tapping it opens the Light tab pre-filled with
/// this spot, which is the handoff the two screens exist to make.
struct SpotLightStrip: View {
    let spot: Spot
    let profile: GearProfile?
    let weather: WeatherService?
    let now: Date
    let action: () -> Void

    @State private var reading: WeatherReading?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Light right now")
                        .font(MapTheme.sectionLabelFont)
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(MapTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MapTheme.accent)
                }

                if let recommendation = advice?.subjectSolution?.primary {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(ExposurePhrasing.aperture(recommendation.aperture))
                            .font(MapTheme.settingFont)
                            .foregroundStyle(MapTheme.primaryText)
                        Text(ExposurePhrasing.shutter(recommendation.shutter))
                            .font(MapTheme.settingFont)
                            .foregroundStyle(MapTheme.primaryText)
                        Text(ExposurePhrasing.iso(recommendation.iso))
                            .font(MapTheme.settingSecondaryFont)
                            .foregroundStyle(MapTheme.secondaryText)
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        ExposurePhrasing.spokenSetting(
                            aperture: recommendation.aperture,
                            shutter: recommendation.shutter,
                            iso: recommendation.iso,
                            sigmaEV: advice?.estimate.sigmaEV ?? 0
                        )
                    )
                }

                Text(sentence)
                    .font(.system(size: 12))
                    .foregroundStyle(MapTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MapTheme.accent.opacity(0.06),
                in: RoundedRectangle(cornerRadius: MapTheme.chipRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                    .stroke(MapTheme.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            // Offline is the ordinary case in the street: the strip falls back
            // to a clear-sky estimate and says so, rather than spinning.
            reading = await weather?.reading(at: spot.coordinate)
        }
    }

    private var advice: Advice? {
        guard let profile else { return nil }
        return LightAdvisor.advise(
            AdviceRequest(
                date: now,
                latitudeDegrees: spot.lat,
                longitudeDegrees: spot.lon,
                cloudCover: reading?.cloudCover,
                weatherFreshness: reading?.freshness ?? .unavailable,
                precipitation: reading?.precipitation ?? .none,
                scene: SpotHandoff.scene(for: spot.openness),
                calibrationOffsetEV: profile.calibrationOffsetEV,
                body: CameraBodyProfile(profile.body),
                lens: LensProfile(profile.lens)
            )
        )
    }

    private var sun: SolarPosition {
        advice?.sun ?? Solar.position(
            date: now,
            latitudeDegrees: spot.lat,
            longitudeDegrees: spot.lon
        )
    }

    /// "Sun 14.7° at 72° NE — the NE-facing façade is lit." Plus the honest
    /// caveat when there is no forecast behind the number.
    private var sentence: String {
        var parts: [String] = []
        if sun.elevationDegrees > 0 {
            parts.append(
                "Sun \(SolarPhrasing.degrees(sun.elevationDegrees))° at "
                    + "\(Int(sun.azimuthDegrees.rounded()))° "
                    + SolarPhrasing.compassPoint(sun.azimuthDegrees)
            )
        } else {
            parts.append("Sun is down — \(SolarPhrasing.degrees(sun.elevationDegrees))°")
        }
        if let side = SolarPhrasing.litFacade(
            streetBearingDegrees: spot.streetBearing,
            sunAzimuthDegrees: sun.azimuthDegrees,
            sunElevationDegrees: sun.elevationDegrees
        ) {
            parts.append("the \(side)-facing façade is lit")
        } else if spot.streetBearing != nil, sun.elevationDegrees > 0 {
            parts.append("the sun runs along the street, so both façades are edge-lit")
        }
        var sentence = parts.joined(separator: " — ") + "."
        if reading?.usesClearSkyFallback ?? true {
            sentence += " No forecast here: this is a clear-sky estimate."
        }
        return sentence
    }
}
