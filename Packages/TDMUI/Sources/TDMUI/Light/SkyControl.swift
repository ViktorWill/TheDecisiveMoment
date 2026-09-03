import SwiftUI
import TDMWeather

/// The five-segment sky control, `docs/SPEC-light.md` "Sky, when there is no
/// WeatherKit".
///
/// Styled exactly like the Scene control in `design/Main.dc.html`: one hairline
/// (#2A2E34) showing through 1 pt gaps as the divider, 44 pt tall segments on
/// #191B1E, the active one filled with the accent #E8A64A and inked in the page
/// colour #101113, 11 pt labels, semibold when active, and a 6 pt radius —
/// the token for controls.
struct SkyControl: View {
    let selection: SkySegment
    let onSelect: (SkySegment) -> Void

    /// #2A2E34 showing through the gaps, which is how the mockup draws the
    /// dividers: a background behind 1 pt spacing rather than borders.
    private static let rule = Color(hex: 0x2A2E34)
    private static let segmentSurface = Color(hex: 0x191B1E)
    private static let accent = Color(hex: 0xE8A64A)
    /// The ink on the accent: the page colour, not black.
    private static let activeInk = Color(hex: 0x101113)
    private static let inactiveInk = Color(hex: 0x9A9DA3)
    private static let height: CGFloat = 44
    private static let radius: CGFloat = 6

    var body: some View {
        HStack(spacing: 1) {
            ForEach(SkySegment.allCases) { segment in
                let isSelected = segment == selection
                Button {
                    onSelect(segment)
                } label: {
                    Text(SkyControl.name(of: segment))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(isSelected ? Self.activeInk : Self.inactiveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.height)
                        .background(isSelected ? Self.accent : Self.segmentSurface)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SkyControl.accessibilityName(of: segment))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .background(Self.rule)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Spelt out here rather than on ``SkySegment``: `TDMWeather` carries no
    /// display strings, same rule as the presets in ``InputControlsView``.
    static func name(of segment: SkySegment) -> String {
        switch segment {
        case .clear: "Clear"
        case .lightHaze: "Haze"
        case .hazySun: "Hazy sun"
        case .cloudyBright: "Bright"
        case .overcast: "Overcast"
        }
    }

    /// The spoken name, which is the spec's full wording — the segment labels
    /// are shortened to fit five across a phone, the meaning is not.
    static func accessibilityName(of segment: SkySegment) -> String {
        switch segment {
        case .clear: "Clear, full sun with distinct shadows"
        case .lightHaze: "Light haze"
        case .hazySun: "Hazy sun, soft shadows"
        case .cloudyBright: "Cloudy bright, no shadows"
        case .overcast: "Overcast"
        }
    }
}

/// The sky control with its label, and — in a build that has a forecast — a way
/// back to it.
///
/// Free build: `onUseForecast` is `nil`, because there is nothing to go back to
/// and the control is the only source there is.
struct SkyPanel: View {
    let selection: SkySegment
    let onSelect: (SkySegment) -> Void
    let onUseForecast: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // 10 / 600 · 0.12 em · upper — the section label of
                // `design/Tokens.dc.html`, in #62666C.
                Text("Sky".uppercased())
                    .font(LightTheme.sectionLabelFont)
                    .kerning(1.2)
                    .foregroundStyle(LightTheme.tertiaryText)
                Spacer(minLength: 8)
                if let onUseForecast {
                    Button("Use the forecast", action: onUseForecast)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LightTheme.accent)
                }
            }
            SkyControl(selection: selection, onSelect: onSelect)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sky")
    }
}

#Preview {
    VStack(spacing: 20) {
        SkyPanel(selection: .hazySun, onSelect: { _ in }, onUseForecast: nil)
        SkyPanel(selection: .clear, onSelect: { _ in }, onUseForecast: {})
    }
    .padding(20)
    .background(LightTheme.background)
    .preferredColorScheme(.dark)
}
