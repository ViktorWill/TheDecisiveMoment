import SwiftUI
import TDMCore
import TDMLight

/// The body picker, `design/Bodies.dc.html`.
///
/// Film first, then digital, oldest to newest inside each — the order of the
/// roster in `docs/SPEC-light.md`. Three of these bodies are not just different
/// numbers in the same shape, and the picker says so on the row: an M7 has A, an
/// M-A has no meter, and an M8 is not full frame.
struct BodyPickerView: View {
    let bodies: [CameraBody]
    let selected: CameraBody?
    /// The lens currently fitted, used for the M8's framing note. `nil` leaves
    /// the note off rather than guessing a focal length.
    var lens: Lens?
    let onSelect: (CameraBody) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Film", bodies: bodies.filter { $0.medium.isFilm })
                section("Digital", bodies: bodies.filter { !$0.medium.isFilm })

                Text("Shutter ladders and ISO ranges are seed values from the manuals. The advisor is exactly as accurate as this table — a wrong top speed produces confident nonsense.")
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
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, bodies: [CameraBody]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(LightTheme.sectionLabelFont)
                .kerning(1.2)
                .foregroundStyle(LightTheme.tertiaryText)

            VStack(spacing: 6) {
                if bodies.isEmpty {
                    // Only reachable if the gear store answered with a partial
                    // roster; the shipped catalogue always has both halves.
                    Text("No \(title.lowercased()) bodies on this device.")
                        .font(LightTheme.captionFont)
                        .foregroundStyle(LightTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(bodies) { body in
                    Button {
                        onSelect(body)
                    } label: {
                        BodyRow(
                            camera: body,
                            isSelected: body.id == selected?.id,
                            lens: lens
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One body: what it is, and what is different about it.
private struct BodyRow: View {
    let camera: CameraBody
    let isSelected: Bool
    let lens: Lens?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shortName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LightTheme.primaryText)
                    Text(BodyPhrasing.specification(camera))
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(LightTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(BodyPhrasing.badges(camera), id: \.text) { badge in
                    BadgeView(badge: badge)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LightTheme.accent)
                }
            }

            // The crop is the one difference that changes the maths rather than
            // the copy, so it gets the numbers rather than a badge.
            if isSelected, !camera.format.isFullFrame {
                CroppedFormatDetail(format: camera.format, lens: lens)
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
                .stroke(borderColour, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// "Leica M6" on the row is redundant when every row says Leica.
    private var shortName: String {
        camera.name.replacingOccurrences(of: "Leica ", with: "")
    }

    private var borderColour: Color {
        if isSelected { return LightTheme.accent }
        // A body with no meter is worth flagging even when it is not selected:
        // it changes how the whole screen works.
        return camera.hasMeter ? LightTheme.hairline : LightTheme.curated.opacity(0.5)
    }
}

/// What the crop actually costs, in the numbers of `docs/EXPOSURE-MODEL.md` §6.
private struct CroppedFormatDetail: View {
    let format: SensorFormat
    let lens: Lens?

    /// The comparison the mockup makes: a 35 mm at f/8, focused at 3 m.
    private static let comparisonAperture = 8.0
    private static let comparisonDistanceMetres = 3.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(LightTheme.hairline).frame(height: 1)

            Text(sentence)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(LightTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 1) {
                zone("Full frame · \(Int(focalLength)) f/8 at 3 m", range(for: .fullFrame), tint: LightTheme.tertiaryText)
                zone("This body", range(for: format), tint: LightTheme.accent)
            }
            .background(LightTheme.hairline)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.top, 12)
    }

    private var focalLength: Double { lens?.focalLengthMillimetres ?? 35 }

    private var sentence: String {
        ExposurePhrasing.croppedFormatSentence(format: format, focalLengthMillimetres: focalLength)
    }

    private func range(for format: SensorFormat) -> String {
        let focus = DepthOfField.range(
            focalLengthMillimetres: focalLength,
            aperture: Self.comparisonAperture,
            focusDistanceMetres: Self.comparisonDistanceMetres,
            circleOfConfusionMillimetres: format.circleOfConfusionMillimetres
        )
        return ExposurePhrasing.zoneComparison(near: focus.nearMetres, far: focus.farMetres)
    }

    private func zone(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .kerning(0.96)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(LightTheme.surface)
    }
}

private struct BadgeView: View {
    let badge: BodyPhrasing.Badge

    var body: some View {
        // The quiet badge is a note rather than a badge in the mockup: plain
        // grey text, its own case, no border.
        if badge.style == .quiet {
            Text(badge.text)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(LightTheme.tertiaryText)
        } else {
            label
        }
    }

    private var label: some View {
        Text(badge.text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .kerning(0.54)
            .foregroundStyle(badge.style == .filled ? LightTheme.background : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(badge.style == .filled ? tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(badge.style == .filled ? Color.clear : tint.opacity(0.5), lineWidth: 1)
            )
    }

    private var tint: Color {
        switch badge.kind {
        case .noMeter: LightTheme.curated
        case .quiet: LightTheme.tertiaryText
        default: LightTheme.accent
        }
    }
}

/// The body picker's strings, kept out of `TDMLight`, which is a maths package.
enum BodyPhrasing {
    struct Badge: Equatable {
        enum Kind: Equatable { case aperturePriority, noMeter, croppedFormat, quiet }
        enum Style: Equatable { case filled, outlined, quiet }
        let text: String
        let kind: Kind
        var style: Style = .outlined
    }

    static func badges(_ body: CameraBody) -> [Badge] {
        var badges: [Badge] = []
        if body.supportsAperturePriority {
            badges.append(Badge(text: "A mode", kind: .aperturePriority))
        }
        if !body.hasMeter {
            badges.append(Badge(text: "No meter", kind: .noMeter))
        }
        if !body.format.isFullFrame {
            badges.append(Badge(text: body.format.name, kind: .croppedFormat, style: .filled))
        }
        // Two generations behind: a dim side street wants more ISO than this
        // sensor has, and that is the difference between an answer and a
        // shortfall, §7d.
        if let sensor = body.iso.sensorRange, sensor.maximum <= 2_500 {
            badges.append(Badge(text: "low ceiling", kind: .quiet, style: .quiet))
        }
        return badges
    }

    /// `1 s – 1/1000 · TTL meter · the roll`, `32 s – 1/8000 · ISO 160 – 2500`.
    static func specification(_ body: CameraBody) -> String {
        var parts: [String] = [ladder(body)]
        if let sensor = body.iso.sensorRange {
            parts.append("ISO \(number(sensor.minimum)) – \(number(sensor.maximum))")
        } else {
            parts.append(body.hasMeter ? "TTL meter · the roll" : "fully mechanical")
        }
        if !body.mechanicalFallbackShutterSpeeds.isEmpty, body.supportsAperturePriority {
            parts.insert(
                ExposurePhrasing.shutter(body.mechanicalFallbackShutterSpeeds.min() ?? 0)
                    + " + " + ExposurePhrasing.shutter(body.mechanicalFallbackShutterSpeeds.max() ?? 0)
                    + " on a flat battery",
                at: 1
            )
        }
        if body.hasElectronicShutter, let fastest = body.fastestShutterInAnyMode {
            parts.insert(ExposurePhrasing.shutter(fastest) + " electronic", at: 1)
        }
        return parts.joined(separator: " · ")
    }

    private static func ladder(_ body: CameraBody) -> String {
        guard let slowest = body.sortedShutterSpeeds.last, let fastest = body.fastestShutter else {
            return "no shutter"
        }
        let mechanical = body.hasElectronicShutter ? " mech" : ""
        return "\(ExposurePhrasing.shutter(slowest)) – \(ExposurePhrasing.shutter(fastest))\(mechanical)"
    }

    /// 50 000 rather than 50000: a five-figure ISO is unreadable otherwise.
    private static func number(_ value: Int) -> String {
        guard value >= 10_000 else { return "\(value)" }
        return "\(value / 1_000) \(String(format: "%03d", value % 1_000))"
    }
}
