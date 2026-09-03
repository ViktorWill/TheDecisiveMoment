import SwiftUI
import TDMLight

/// The signature element: a picture of the lens barrel.
///
/// The engraved marks run along a logarithmic scale, exactly as they sit on a
/// rangefinder focus ring; the recommended mark is highlighted and the sharp
/// range is drawn as a band across it. Dragging snaps to the next engraved mark
/// and the band follows, live.
///
/// Honesty rule 4 is structural here rather than checked: the only positions
/// this view can express are the marks in `lens.sortedDistanceMarks`, so it
/// cannot show a distance the lens has not got.
struct ZoneScaleView: View {
    let lens: LensProfile
    let cameraBody: CameraBodyProfile
    let aperture: Double
    /// The mark the barrel is set to, metres. Always one of the lens's marks.
    @Binding var markMetres: Double
    /// The mark the solver recommends, for the "back to the recommendation"
    /// affordance when the user has dragged away from it.
    let recommendedMarkMetres: Double?

    private var marks: [Double] { lens.sortedDistanceMarks }

    private var range: FocusRange {
        ZoneFocus.range(lens: lens, body: cameraBody, markMetres: markMetres, aperture: aperture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GeometryReader { geometry in
                let layout = ScaleLayout(marks: marks, width: geometry.size.width)

                ZStack(alignment: .topLeading) {
                    barrel
                    sharpBand(layout: layout)
                    ticksAndLabels(layout: layout)
                    index(layout: layout)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let snapped = layout.mark(nearestTo: value.location.x) else { return }
                            if snapped != markMetres {
                                markMetres = snapped
                                #if canImport(UIKit)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                            }
                        }
                )
            }
            .frame(height: 92)
            .accessibilityElement()
            .accessibilityLabel("Focus scale")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                guard let index = marks.firstIndex(of: markMetres) else { return }
                let next = direction == .increment ? index + 1 : index - 1
                if marks.indices.contains(next) { markMetres = marks[next] }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(
                ExposurePhrasing.zoneSentence(
                    markMetres: markMetres,
                    near: range.nearMetres,
                    far: range.farMetres
                )
            )
            .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(LightTheme.primaryText)

            Spacer(minLength: 8)

            if let recommendedMarkMetres, recommendedMarkMetres != markMetres {
                Button("Recommended") { markMetres = recommendedMarkMetres }
                    .font(LightTheme.labelFont)
                    .foregroundStyle(LightTheme.accent)
                    .buttonStyle(.plain)
            }
        }
    }

    /// The barrel itself: a dark cylinder, lit from above.
    private var barrel: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.20, blue: 0.22),
                        Color(red: 0.12, green: 0.12, blue: 0.14),
                        Color(red: 0.06, green: 0.06, blue: 0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .frame(height: 64)
            .offset(y: 14)
    }

    /// The depth of field, drawn where it actually falls on the scale.
    private func sharpBand(layout: ScaleLayout) -> some View {
        let near = layout.position(of: range.nearMetres)
        let far = layout.position(of: range.reachesInfinity ? .infinity : range.farMetres)
        let start = min(near, far)
        let width = max(4, abs(far - near))

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [LightTheme.accent.opacity(0.45), LightTheme.accent.opacity(0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: 52)
            .offset(x: start, y: 20)
            .animation(.snappy(duration: 0.18), value: markMetres)
            .animation(.snappy(duration: 0.18), value: aperture)
    }

    private func ticksAndLabels(layout: ScaleLayout) -> some View {
        ForEach(marks, id: \.self) { mark in
            let x = layout.position(of: mark)
            let isSet = mark == markMetres

            VStack(spacing: 4) {
                Text(ExposurePhrasing.distance(mark).replacingOccurrences(of: " m", with: ""))
                    .font(.system(size: isSet ? 14 : 12, weight: isSet ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isSet ? LightTheme.accent : LightTheme.secondaryText)
                Rectangle()
                    .fill(isSet ? LightTheme.accent : LightTheme.secondaryText.opacity(0.7))
                    .frame(width: isSet ? 2 : 1, height: isSet ? 20 : 12)
            }
            .frame(width: 46)
            .position(x: x, y: 22)
        }
    }

    /// The index line the barrel is set against — the fixed mark on the lens
    /// mount, not on the ring.
    private func index(layout: ScaleLayout) -> some View {
        Rectangle()
            .fill(LightTheme.primaryText.opacity(0.9))
            .frame(width: 2, height: 72)
            .position(x: layout.position(of: markMetres), y: 46)
            .animation(.snappy(duration: 0.18), value: markMetres)
    }

    private var accessibilityValue: String {
        ExposurePhrasing.zoneSentence(
            markMetres: markMetres,
            near: range.nearMetres,
            far: range.farMetres
        )
    }
}

/// Maps engraved marks to x positions, and back.
///
/// A focus scale is roughly logarithmic, so this one is too. `∞` gets its own
/// slot at the right-hand end, because `log(∞)` is not a position.
struct ScaleLayout {
    let marks: [Double]
    let width: CGFloat
    private let inset: CGFloat = 26

    /// x for a distance in metres. Distances between marks land between them,
    /// which is what lets the depth-of-field band be drawn honestly even though
    /// only marks can be selected.
    func position(of metres: Double) -> CGFloat {
        let finite = marks.filter(\.isFinite)
        guard let low = finite.first, let high = finite.last, high > low else {
            return width / 2
        }
        let usable = width - 2 * inset
        // The ∞ mark, when the lens has one, owns the last eighth of the scale.
        let hasInfinity = marks.contains { !$0.isFinite }
        let finiteWidth = usable * (hasInfinity ? 0.86 : 1)

        guard metres.isFinite else { return inset + usable }
        let clamped = min(max(metres, low), high)
        let fraction = (log(clamped) - log(low)) / (log(high) - log(low))
        return inset + finiteWidth * fraction
    }

    /// The engraved mark nearest an x position — the only thing a drag can pick.
    func mark(nearestTo x: CGFloat) -> Double? {
        marks.min { abs(position(of: $0) - x) < abs(position(of: $1) - x) }
    }
}
