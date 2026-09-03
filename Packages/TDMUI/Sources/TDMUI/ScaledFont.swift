import SwiftUI

/// A point size from `design/`, scaled by the user's text size.
///
/// The mockups are exact, and the tokens are lifted from them, so the type
/// scale is written in points rather than in `Font.TextStyle`. A fixed point
/// size does not move when someone turns Larger Text up, which on the primary
/// flows is the difference between an app that can be read and one that cannot.
/// This keeps the mockup's size at the default setting and scales from there.
///
/// - Parameter maximumScale: A ceiling on the factor. The readout figures are
///   34 pt already; at the largest accessibility size an uncapped 34 pt would
///   push the zone sentence off the screen, and the answer would be less
///   legible rather than more.
struct ScaledFont: ViewModifier {
    let size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
    var monospacedDigit = false
    var maximumScale: CGFloat = 3

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let font = Font.system(
            size: size * min(scale, maximumScale),
            weight: weight,
            design: design
        )
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

extension View {
    /// `design/` point size, honoured at the default text size and scaled from
    /// there.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        monospacedDigit: Bool = false,
        maximumScale: CGFloat = 3
    ) -> some View {
        modifier(
            ScaledFont(
                size: size,
                weight: weight,
                design: design,
                monospacedDigit: monospacedDigit,
                maximumScale: maximumScale
            )
        )
    }
}
