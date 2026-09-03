import SwiftUI
import TDMLight

/// Neighbouring solutions, as cards. Tapping one promotes it to the top.
///
/// Each card carries the zone the solver worked out for it, so opening up a stop
/// visibly collapses the sharp range — which is the tradeoff the screen is
/// trying to teach.
struct AlternativesRowView: View {
    let alternatives: [ExposureRecommendation]
    let onPromote: (ExposureRecommendation) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alternative in
                    Button {
                        onPromote(alternative)
                    } label: {
                        AlternativeCard(recommendation: alternative)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

private struct AlternativeCard: View {
    let recommendation: ExposureRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(ExposurePhrasing.aperture(recommendation.aperture)) · \(ExposurePhrasing.shutter(recommendation.shutter))")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(LightTheme.primaryText)

            if let zone = recommendation.zone {
                Text(zoneText(zone))
                    .font(.system(size: 13, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(LightTheme.secondaryText)
            }

            Text(ExposurePhrasing.iso(recommendation.iso))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LightTheme.secondaryText.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 140, alignment: .leading)
        .background(LightTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Promotes this setting to the top of the screen")
    }

    private func zoneText(_ zone: FocusRange) -> String {
        zone.reachesInfinity
            ? "\(ExposurePhrasing.sharpLimit(zone.nearMetres)) → ∞"
            : "\(ExposurePhrasing.sharpLimit(zone.nearMetres)) → \(ExposurePhrasing.sharpLimit(zone.farMetres))"
    }
}
