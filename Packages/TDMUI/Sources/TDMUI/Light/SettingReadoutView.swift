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
            column("Aperture", ExposurePhrasing.aperture(recommendation.aperture))

            if let compensation = recommendation.compensationEV {
                // Aperture priority: there is no shutter to set. The body picks
                // one, steplessly, and what the photographer sets instead is the
                // compensation dial.
                column("Compensation", ExposurePhrasing.compensation(compensation))
            } else {
                column("Shutter", ExposurePhrasing.shutter(recommendation.shutter, sigmaEV: sigmaEV))
            }

            if let roll {
                // Context, not a control: the roll is what it is until it is
                // rewound, and the screen must not invite a tap here.
                VStack(alignment: .leading, spacing: 5) {
                    label("Loaded", tint: LightTheme.tertiaryText)
                    Text(ExposurePhrasing.loadedRoll(roll))
                        .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
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
                        .font(LightTheme.readoutFont)
                        .foregroundStyle(LightTheme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(ExposurePhrasing.raiseISO(to: recommendation.iso))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func column(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            label(title, tint: LightTheme.tertiaryText)
            Text(value)
                .font(LightTheme.readoutFont)
                .foregroundStyle(LightTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func label(_ title: String, tint: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .kerning(1.08)
            .foregroundStyle(tint)
    }

    /// What sits under the readout on film: the cost of the rating, stated
    /// wherever the ISO appears rather than buried in the gear screen.
    static func rollFootnote(_ roll: LoadedRoll) -> String? {
        guard let cost = roll.cost else { return nil }
        return "\(roll.signedStops) stops · \(cost.lowercased())"
    }
}
