import SwiftUI
import TDMCore
import TDMLight

/// The screen for when nothing works, `design/NoSolution.dc.html`.
///
/// An empty list of alternatives would be the wrong answer: the reason *is* the
/// answer. "HP5 400 is 0.9 stops short here" tells the photographer what to do
/// with the next twenty minutes, and each lever below re-solves when tapped.
struct NoSolutionView: View {
    let shortfall: ExposureShortfall
    let roll: LoadedRoll?
    /// The body, so a sensor that has run out says so in its own terms: an M8
    /// at ISO 2500 is short in exactly the way a roll is, and the levers it is
    /// offered do not include pushing something that is not there.
    let cameraBody: CameraBodyProfile?
    /// The floor the solve was run against, quoted in the "drop to" lever.
    let handheldFloorSeconds: TimeInterval
    let sigmaEV: Double
    let onApply: (ExposureLever) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(headline)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(LightTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(shortfallSentence + " " + detail)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(LightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !shortfall.levers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What would work".uppercased())
                        .font(LightTheme.sectionLabelFont)
                        .kerning(1.2)
                        .foregroundStyle(LightTheme.tertiaryText)

                    ForEach(Array(shortfall.levers.enumerated()), id: \.offset) { index, lever in
                        Button {
                            onApply(lever)
                        } label: {
                            LeverCard(
                                lever: lever,
                                floorSeconds: handheldFloorSeconds,
                                sigmaEV: sigmaEV,
                                isPrimary: index == 0
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(salvageNote)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(LightTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(LightTheme.hairline)
                        .frame(width: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// `Leica M8 at ISO 2500 is 2.3 stops short here.` on a sensor,
    /// `HP5 400 is 0.9 stops short here.` on a roll.
    private var shortfallSentence: String {
        guard let cameraBody else { return ExposurePhrasing.shortfallSentence(shortfall, roll: roll) }
        return ExposurePhrasing.shortfallSentence(shortfall, body: cameraBody)
    }

    private var headline: String {
        switch shortfall.reason {
        case .emptyGearProfile: "No gear to work with"
        case .strategyConstraintsUnsatisfiable: "Not with this strategy"
        case .noSettingWithinTolerance: roll == nil ? "Not on this sensor" : "Not on this roll"
        case .strategyUnavailableOnBody: "Not on this body"
        }
    }

    private var detail: String {
        switch shortfall.reason {
        case .emptyGearProfile:
            return "This profile has no shutter speeds, apertures or ISO."
        case .strategyConstraintsUnsatisfiable:
            return "Nothing on the dial satisfies it here."
        case .strategyUnavailableOnBody:
            return "This body will not pick the shutter itself.
        case .noSettingWithinTolerance:
            return shortfall.sense == .needsMoreLight
                ? "Nothing on the dial reaches it hand-held."
                : "Even the narrowest aperture at the fastest speed lets too much through."
        }
    }

    /// The paragraph the mockup ends on: two stops is the line between a
    /// salvageable roll and the wrong film.
    private var salvageNote: String {
        guard roll != nil else {
            return shortfall.isSalvageable
                ? "Under two stops short — the ceiling or a wider aperture would close it."
                : "More than two stops. This scene needs a different approach."
        }
        return shortfall.isSalvageable
            ? "Under two stops short, so the roll is salvageable. Past two, the honest answer is that this is the wrong film for this light — and that is worth knowing before you burn the frame."
            : "More than two stops. This is the wrong film for this light, and that is worth knowing before you burn the frame."
    }
}

/// One lever: what to do, what it costs, and the setting it buys.
private struct LeverCard: View {
    let lever: ExposureLever
    let floorSeconds: TimeInterval
    let sigmaEV: Double
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isPrimary ? LightTheme.accent : LightTheme.secondaryText)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(ExposurePhrasing.leverTitle(lever))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPrimary ? LightTheme.primaryText : LightTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                Text(ExposurePhrasing.leverDetail(lever, floor: floorSeconds))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(LightTheme.tertiaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let setting {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ExposurePhrasing.aperture(setting.aperture))
                        .font(.system(size: 14, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(isPrimary ? LightTheme.accent : LightTheme.secondaryText)
                    Text(ExposurePhrasing.shutter(setting.shutter, sigmaEV: sigmaEV))
                        .font(.system(size: 12, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(isPrimary ? LightTheme.secondaryText : LightTheme.tertiaryText)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LightTheme.tertiaryText)
            }
        }
        .padding(14)
        .background(LightTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPrimary ? LightTheme.accent : LightTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Applies this and solves again")
    }

    private var setting: ExposureRecommendation? {
        switch lever {
        case let .rate(_, setting), let .lowerFloor(_, setting): setting
        default: nil
        }
    }

    private var symbol: String {
        switch lever {
        case .rate: "arrow.up"
        case .lowerFloor: "clock"
        case .neutralDensity: "circle.lefthalf.filled"
        case .differentRoll: "film"
        case .raiseCeiling: "arrow.up.to.line"
        }
    }
}
