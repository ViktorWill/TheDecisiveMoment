import SwiftUI

/// Dark-first tokens. The app is used at dusk and at night, and a white screen
/// at blue hour ruins night vision and exposure judgement.
///
/// Nothing here is pure white: the brightest surface is a warm off-white, which
/// reads at arm's length in sunlight without flaring in the dark.
public enum LightTheme {
    /// The page. Not black — a very dark neutral keeps the panels visible.
    public static let background = Color(red: 0.04, green: 0.04, blue: 0.05)
    /// A panel sitting on the page.
    public static let surface = Color(red: 0.09, green: 0.09, blue: 0.11)
    /// A control sitting on a panel.
    public static let raised = Color(red: 0.15, green: 0.15, blue: 0.18)
    /// The answer.
    public static let primaryText = Color(red: 0.96, green: 0.95, blue: 0.92)
    /// Labels and units.
    public static let secondaryText = Color(red: 0.66, green: 0.66, blue: 0.70)
    /// The engraved-mark accent, and anything the user has chosen.
    public static let accent = Color(red: 0.98, green: 0.72, blue: 0.29)
    /// Golden hour.
    public static let golden = Color(red: 0.98, green: 0.66, blue: 0.24)
    /// Blue hour.
    public static let blue = Color(red: 0.36, green: 0.52, blue: 0.86)
    /// Something the app is unsure about, or is warning against.
    public static let caution = Color(red: 0.92, green: 0.45, blue: 0.36)

    /// The one line the screen exists for. Monospaced digits so the numbers do
    /// not dance as the model updates.
    public static let answerFont = Font.system(size: 34, weight: .semibold, design: .rounded)
        .monospacedDigit()
    public static let zoneFont = Font.system(size: 20, weight: .medium, design: .rounded)
    public static let conditionsFont = Font.system(size: 15, weight: .regular, design: .rounded)
        .monospacedDigit()
    public static let labelFont = Font.system(size: 12, weight: .semibold, design: .rounded)
}

/// A panel: rounded, raised a little off the page, dark.
struct PanelModifier: ViewModifier {
    var title: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(LightTheme.labelFont)
                    .kerning(0.8)
                    .foregroundStyle(LightTheme.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LightTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func panel(_ title: String? = nil) -> some View {
        modifier(PanelModifier(title: title))
    }
}
