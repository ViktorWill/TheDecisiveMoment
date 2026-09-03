import SwiftUI
import TDMCore
import TDMLight

/// The answer as three columns — aperture, shutter, and the ISO, which is the
/// whole difference between the two modes, `docs/SPEC-light.md` "Two modes".
///
/// On film the ISO is a fact of the loaded roll, so it is rendered dimmed as
/// context and reads `HP5 400 @ 1600 (+2)`. On a sensor it is the variable the
/// solver moved, so it is rendered at full weight, in the accent, and labelled
/// as a change: `Raise ISO to · 1600`.
///
/// Values are lifted from `design/Digital.dc.html`: 34 / 500 readout figures,
/// 9 pt labels, 26 pt between columns, 5 pt between a label and its figure.
struct SettingReadoutView: View {
    let recommendation: ExposureRecommendation
    /// The roll, when film is loaded. Its presence is what switches the mode.
    let roll: LoadedRoll?
    /// Hedged phrasing when σ is too wide for the digits, honesty rule 1.
    let sigmaEV: Double

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            column(
                "Aperture",
                ExposurePhrasing.aperture(recommendation.aperture),
                spoken: ExposurePhrasing.spokenAperture(recommendation.aperture)
            )

            if let compensation = recommendation.compensationEV {
                // Aperture priority: there is no shutter to set. The body picks
                // one, steplessly, and what the photographer sets instead is the
                // compensation dial.
                column(
                    "Compensation",
                    ExposurePhrasing.compensation(compensation),
                    spoken: ExposurePhrasing.spokenCompensation(compensation)
                )
            } else {
                column(
                    "Shutter",
                    ExposurePhrasing.shutter(recommendation.shutter, sigmaEV: sigmaEV),
                    spoken: ExposurePhrasing.spokenShutter(recommendation.shutter, sigmaEV: sigmaEV)
                )
            }

            if let roll {
                // Context, not a control: the roll is what it is until it is
                // rewound, and the screen must not invite a tap here.
                VStack(alignment: .leading, spacing: 5) {
                    label("Loaded", tint: LightTheme.tertiaryText)
                    Text(ExposurePhrasing.loadedRoll(roll))
                        .scaledFont(size: 15, weight: .medium, design: .rounded, monospacedDigit: true, maximumScale: 1.6)
                        .foregroundStyle(LightTheme.secondaryText.opacity(0.7))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loaded film \(ExposurePhrasing.loadedRoll(roll)). Not a control.")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    label("Raise ISO to", tint: LightTheme.accent)
                    Text("\(recommendation.iso)")
                        .scaledFont(size: LightTheme.readoutSize, weight: .medium, design: .rounded, monospacedDigit: true, maximumScale: 1.4)
                        .foregroundStyle(LightTheme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(ExposurePhrasing.raiseISO(to: recommendation.iso))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// - Parameter spoken: The same figure as a person would say it. `f/8`
    ///   read aloud is "f slash 8", and a shutter speed is worse; the engraved
    ///   form stays on screen and the sentence goes to VoiceOver.
    private func column(_ title: String, _ value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            label(title, tint: LightTheme.tertiaryText)
            Text(value)
                .scaledFont(size: LightTheme.readoutSize, weight: .medium, design: .rounded, monospacedDigit: true, maximumScale: 1.4)
                .foregroundStyle(LightTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(spoken)")
    }

    private func label(_ title: String, tint: Color) -> some View {
        // `kerning` is a `Text` modifier, so it has to come before the font
        // one, which returns a `View`.
        Text(title.uppercased())
            .kerning(1.08)
            .scaledFont(size: 9, weight: .semibold, design: .rounded, maximumScale: 1.8)
            .foregroundStyle(tint)
    }

    /// What sits under the readout on film: the cost of the rating, stated
    /// wherever the ISO appears rather than buried in the gear screen.
    static func rollFootnote(_ roll: LoadedRoll) -> String? {
        guard let cost = roll.cost else { return nil }
        return "\(roll.signedStops) stops · \(cost.lowercased())"
    }
}
