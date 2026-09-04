import SwiftUI
import TDMCore
import TDMLight

/// The lens picker — the mirror of `BodyPickerView`. Wide to long, the order
/// `GearCatalogue.lenses` already ships in.
///
/// No badges here: a lens has no meter to lack and no priority mode to
/// support. What it has that changes the advice is its aperture ladder and its
/// distance marks, so those are what the row shows.
struct LensPickerView: View {
    let lenses: [Lens]
    let selected: Lens?
    let onSelect: (Lens) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    if lenses.isEmpty {
                        // Only reachable if the gear store answered with a
                        // partial roster; the shipped catalogue always has one.
                        Text("No lenses on this device.")
                            .font(LightTheme.captionFont)
                            .foregroundStyle(LightTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(lenses) { lens in
                        Button {
                            onSelect(lens)
                        } label: {
                            LensRow(lens: lens, isSelected: lens.id == selected?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Aperture ladders and distance marks are engraved values from the barrel. The zone-focus advice is exactly as accurate as this table — a mark the lens does not have makes the advice unusable.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(LightTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(LightTheme.hairline).frame(width: 1)
                    }
            }
            .padding(20)
        }
        .background(LightTheme.background)
        .navigationTitle("Lens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One lens: its focal length, its widest stop, and where the scale ends.
private struct LensRow: View {
    let lens: Lens
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lens.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LightTheme.primaryText)
                Text(specification)
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(LightTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LightTheme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? LightTheme.surface : LightTheme.background.opacity(0.6))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LightTheme.accent : LightTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// `f/1.4 – f/16 · 0.7 m – ∞`, the two things the barrel actually offers.
    private var specification: String {
        let apertures = lens.sortedApertures
        let widest = apertures.first.map(ExposurePhrasing.aperture) ?? "—"
        let narrowest = apertures.last.map(ExposurePhrasing.aperture) ?? "—"
        let closest = ExposurePhrasing.distance(lens.minimumFocusMetres)
        return "\(widest) – \(narrowest) · \(closest) – ∞"
    }
}
