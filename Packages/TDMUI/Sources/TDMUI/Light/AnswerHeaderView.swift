import SwiftUI
import TDMCore
import TDMLight

/// The three lines the feature exists for:
///
/// ```
///         f/8 · 1/250 · ISO 400
///      scale to 3 m — sharp 1.9 to 7.2 m
///         EV 14.1 ± 0.5 · sun 14.7° · 20% cloud
/// ```
///
/// If the user reads only this and nothing else, the screen has done its job.
struct AnswerHeaderView: View {
    let advice: Advice
    let recommendation: ExposureRecommendation?
    /// The loaded roll, which switches the header into analog mode: the ISO
    /// becomes dimmed context rather than a solved value, §7c.
    let roll: LoadedRoll?
    /// The floor this solve was run against, quoted by the no-solution levers.
    let handheldFloorSeconds: TimeInterval
    /// Applies a lever from the no-solution screen and re-solves.
    let onApplyLever: (ExposureLever) -> Void
    /// The cover the estimate was built from, `nil` when the model fell back to
    /// clear sky. Passed in rather than re-derived so this line can never
    /// disagree with the EV above it.
    let cloudCover: Double?
    let isStaleWeather: Bool
    /// Whether the cover came from the photographer rather than a forecast.
    let isReportedWeather: Bool
    /// Opens the sky control over the cloud figure, `docs/SPEC-light.md` "Sky,
    /// when there is no WeatherKit". `nil` where there is nothing to open —
    /// a build with no forecast has the control on screen already.
    let onTapCloud: (() -> Void)?
    let isScrubbing: Bool
    let scrubbedTo: Date
    /// The body the answer is for, so a sensor that has run out of ISO says so
    /// in its own terms rather than a roll's.
    let cameraBody: CameraBodyProfile?
    /// `frames like a 47 mm` on a cropped body. Framing only.
    let framingNote: String?

    var body: some View {
        VStack(spacing: 10) {
            if isScrubbing {
                Text(scrubbedTo, format: .dateTime.hour().minute())
                    .font(LightTheme.labelFont)
                    .foregroundStyle(LightTheme.accent)
                    .accessibilityLabel("Showing the model for \(scrubbedTo.formatted(date: .omitted, time: .shortened))")
            }

            if !advice.predictsSubjectExposure {
                SilhouetteView(background: recommendation, sigmaEV: advice.estimate.sigmaEV)
            } else if let recommendation {
                SettingReadoutView(
                    recommendation: recommendation,
                    roll: roll,
                    sigmaEV: advice.estimate.sigmaEV
                )

                if recommendation.isAutomatic {
                    Text(ExposurePhrasing.automaticShutter(recommendation.shutter))
                        .font(LightTheme.captionFont)
                        .foregroundStyle(LightTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(
                            "The body will pick about \(ExposurePhrasing.spokenShutter(recommendation.shutter))"
                        )
                }

                if let roll, let footnote = SettingReadoutView.rollFootnote(roll) {
                    Text(footnote)
                        .font(LightTheme.captionFont)
                        .foregroundStyle(LightTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let zone = recommendation.zone, let mark = advice.focusMarkMetres {
                    Text(
                        ExposurePhrasing.zoneSentence(
                            markMetres: mark,
                            near: zone.nearMetres,
                            far: zone.farMetres
                        )
                    )
                    .scaledFont(size: 20, weight: .medium, design: .rounded, maximumScale: 1.6)
                    .foregroundStyle(LightTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(
                        ExposurePhrasing.spokenZoneSentence(
                            markMetres: mark,
                            near: zone.nearMetres,
                            far: zone.farMetres
                        )
                    )
                }

                if let framingNote {
                    Text(framingNote)
                        .font(LightTheme.captionFont)
                        .foregroundStyle(LightTheme.tertiaryText)
                }
            } else if let shortfall = advice.shortfall {
                NoSolutionView(
                    shortfall: shortfall,
                    roll: roll,
                    cameraBody: cameraBody,
                    handheldFloorSeconds: handheldFloorSeconds,
                    sigmaEV: advice.estimate.sigmaEV,
                    onApply: onApplyLever
                )
            } else {
                UnsolvableView(error: nil, estimate: advice.estimate)
            }

            conditions

            if advice.estimate.usedClearSkyFallback {
                Label("No weather · clear sky assumed, uncertainty widened", systemImage: "wifi.slash")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LightTheme.caution)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// The conditions line. In a build with a forecast the cloud figure is a
    /// button — an observation beats a forecast, and the photographer is the
    /// one standing under the sky.
    @ViewBuilder
    private var conditions: some View {
        if let onTapCloud {
            HStack(spacing: 6) {
                Text(conditionsLead)
                Text("·")
                Button(action: onTapCloud) {
                    HStack(spacing: 4) {
                        Text(cloudPhrase)
                        Image(systemName: "cloud.sun")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(LightTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(spokenCloudPhrase). Report the sky yourself")
            }
            .scaledFont(size: 15, design: .rounded, monospacedDigit: true, maximumScale: 1.6)
            .foregroundStyle(LightTheme.secondaryText)
            .accessibilityElement(children: .contain)
        } else {
            Text(conditionsLine)
                .scaledFont(size: 15, design: .rounded, monospacedDigit: true, maximumScale: 1.6)
                .foregroundStyle(LightTheme.secondaryText)
                .multilineTextAlignment(.center)
                .accessibilityLabel(spokenConditionsLine)
        }
    }

    /// The cover the line is allowed to quote: `nil` once the model has fallen
    /// back to clear sky, so the figure can never contradict the EV above it.
    private var quotedCloudCover: Double? {
        advice.estimate.usedClearSkyFallback ? nil : cloudCover
    }

    private var cloudPhrase: String {
        ExposurePhrasing.cloud(
            cover: quotedCloudCover,
            isStale: isStaleWeather,
            isReported: isReportedWeather
        )
    }

    private var spokenCloudPhrase: String {
        ExposurePhrasing.spokenCloud(
            cover: quotedCloudCover,
            isStale: isStaleWeather,
            isReported: isReportedWeather
        )
    }

    /// Everything left of the cloud figure.
    private var conditionsLead: String {
        let estimate = advice.estimate
        let ev = ExposurePhrasing.exposureValue(estimate.ev100, sigmaEV: estimate.sigmaEV)
        return "\(ev) · \(ExposurePhrasing.sunElevation(advice.sun.elevationDegrees))"
    }

    private var conditionsLine: String {
        let estimate = advice.estimate
        let ev = ExposurePhrasing.exposureValue(estimate.ev100, sigmaEV: estimate.sigmaEV)
        let conditions = ExposurePhrasing.conditions(
            sunElevationDegrees: advice.sun.elevationDegrees,
            cloudCover: quotedCloudCover,
            isStale: isStaleWeather,
            isReported: isReportedWeather
        )
        return "\(ev) · \(conditions)"
    }

    /// The same line, said rather than engraved: `±` and `°` are symbols a
    /// screen reader either skips or mispronounces.
    private var spokenConditionsLine: String {
        let estimate = advice.estimate
        let ev = ExposurePhrasing.spokenExposureValue(estimate.ev100, sigmaEV: estimate.sigmaEV)
        let conditions = ExposurePhrasing.spokenConditions(
            sunElevationDegrees: advice.sun.elevationDegrees,
            cloudCover: quotedCloudCover,
            isStale: isStaleWeather,
            isReported: isReportedWeather
        )
        return "\(ev), \(conditions)"
    }
}

/// Honesty rule 5: back-lit is a warning, not a number.
///
/// The solve is still shown, but only under the label of what it actually is —
/// an exposure for the *background* — so it cannot read as a prediction about
/// the face.
private struct SilhouetteView: View {
    let background: ExposureRecommendation?
    let sigmaEV: Double

    var body: some View {
        VStack(spacing: 8) {
            Text("Back-lit — silhouette")
                .font(LightTheme.answerFont)
                .foregroundStyle(LightTheme.caution)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("The model cannot predict a back-lit subject. Meter off the face, or expose for the sky and take the shape.")
                .font(LightTheme.zoneFont)
                .foregroundStyle(LightTheme.secondaryText)
                .multilineTextAlignment(.center)
            if let background {
                Text(
                    "Background: " + ExposurePhrasing.setting(
                        aperture: background.aperture,
                        shutter: background.shutter,
                        iso: background.iso,
                        sigmaEV: sigmaEV
                    )
                )
                .font(LightTheme.conditionsFont)
                .foregroundStyle(LightTheme.secondaryText)
                .accessibilityLabel(
                    "Background: " + ExposurePhrasing.spokenSetting(
                        aperture: background.aperture,
                        shutter: background.shutter,
                        iso: background.iso,
                        sigmaEV: sigmaEV
                    )
                )
            }
        }
    }
}

/// What the screen says when the gear cannot expose the light. The honest
/// answer is "not with this", plus the number so the user can work around it.
private struct UnsolvableView: View {
    let error: ExposureSolverError?
    let estimate: LightEstimate

    var body: some View {
        VStack(spacing: 8) {
            Text("No setting on this gear")
                .font(LightTheme.answerFont)
                .foregroundStyle(LightTheme.caution)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(detail)
                .font(LightTheme.zoneFont)
                .foregroundStyle(LightTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var detail: String {
        switch error {
        case .noSettingWithinTolerance:
            "The light is outside this body and lens. Open up, change film, or accept a slower shutter."
        case .strategyConstraintsUnsatisfiable(.zoneFocus):
            "Nothing satisfies zone focus here. Try another strategy."
        case .strategyConstraintsUnsatisfiable(.freezeMotion):
            "Nothing satisfies freeze motion here. Try another strategy."
        case .strategyConstraintsUnsatisfiable(.subjectIsolation):
            "Nothing satisfies isolate subject here. Try another strategy."
        case .strategyConstraintsUnsatisfiable(.availableLight):
            "Nothing satisfies available light here. Try another strategy."
        case .strategyConstraintsUnsatisfiable(.aperturePriority):
            "Nothing satisfies aperture priority here. Try another strategy."
        case .strategyUnavailableOnBody(.aperturePriority):
            "This body will not pick the shutter itself. Only an M7 has A."
        case .strategyUnavailableOnBody:
            "This body cannot be set that way. Try another strategy."
        case .emptyGearProfile:
            "This gear profile has no shutter speeds, apertures or ISO to work with."
        case nil:
            "Pick a gear profile to get a setting."
        }
    }
}
