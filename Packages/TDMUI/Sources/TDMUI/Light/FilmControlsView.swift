import SwiftUI
import TDMCore
import TDMLight

/// The ISO ceiling, `design/Digital.dc.html`.
///
/// The ceiling belongs to the photographer, not to the sensor: past it the file
/// is not worth having, and the solver says it is short rather than exceeding
/// it, `docs/EXPOSURE-MODEL.md` §7d. A chip row rather than a slider — every
/// other row on this screen is two taps, pick from the options
/// (`InputControlsView`), and every value here already is one: `ladder` is the
/// body's own real full-stop stops, not a continuous range with a step size.
struct ISOCeilingView: View {
    /// The body's ISO ladder, ascending.
    let ladder: [Int]
    let ceiling: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("ISO ceiling".uppercased())
                    .font(LightTheme.sectionLabelFont)
                    .kerning(1.2)
                    .foregroundStyle(LightTheme.tertiaryText)
                Spacer()
                Text(BodyPhrasing.number(ceiling))
                    .font(.system(size: 12, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(LightTheme.primaryText)
            }

            if ladder.count > 1 {
                ChipPicker(
                    values: ladder,
                    title: BodyPhrasing.number,
                    selection: Binding(get: { ceiling }, set: onChange)
                )
                .accessibilityLabel("ISO ceiling")
            }

            Text("Past this the file is not worth having. The solver will say it is short rather than exceed it.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LightTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The film block of `design/Gear.dc.html`: which stock is loaded, and what it
/// is rated at.
///
/// The stock carries the medium, so choosing one here changes the solver's
/// latitude and bias — that is why the block states them.
struct FilmBlockView: View {
    let roll: LoadedRoll
    let onChange: (LoadedRoll) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loaded film".uppercased())
                        .font(LightTheme.sectionLabelFont)
                        .kerning(1.2)
                        .foregroundStyle(LightTheme.tertiaryText)
                    Text(roll.stock.name)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(LightTheme.primaryText)
                    Text(latitudeLine)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(LightTheme.tertiaryText)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(roll.stock.boxSpeed)")
                        .font(.system(size: 22, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(LightTheme.secondaryText.opacity(0.75))
                    Text("box".uppercased())
                        .font(LightTheme.sectionLabelFont)
                        .kerning(1.2)
                        .foregroundStyle(LightTheme.tertiaryText)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Stock".uppercased())
                    .font(LightTheme.sectionLabelFont)
                    .kerning(1.2)
                    .foregroundStyle(LightTheme.tertiaryText)
                ChipPicker(
                    values: FilmStock.catalogue,
                    title: { $0.shortName },
                    selection: Binding(
                        get: { roll.stock },
                        // A new stock starts at its own box speed: carrying a
                        // push across stocks would silently rate Velvia at 1600.
                        set: { onChange(LoadedRoll(stock: $0)) }
                    )
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rated at".uppercased())
                    .font(LightTheme.sectionLabelFont)
                    .kerning(1.2)
                    .foregroundStyle(LightTheme.tertiaryText)
                ChipPicker(
                    values: roll.availableRatings,
                    title: { "\($0)" },
                    selection: Binding(
                        get: { roll.ratedAt },
                        set: { onChange(LoadedRoll(stock: roll.stock, ratedAt: $0)) }
                    )
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(ExposurePhrasing.loadedRoll(roll))
                    .font(.system(size: 13, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(LightTheme.accent)
                Spacer()
                Text("shown wherever ISO appears")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(LightTheme.tertiaryText)
            }

            Text(costLine)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LightTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `B&W negative · +3 / −1 latitude · bias +⅓`, as the mockup states it.
    private var latitudeLine: String {
        let medium = roll.medium
        return "\(medium.displayName) · \(medium.latitude.summary) latitude · bias \(biasFraction)"
    }

    private var biasFraction: String {
        switch roll.medium {
        case .blackAndWhiteNegative: "+⅓"
        case .colourNegative: "+⅔"
        case .slide, .digital: "−⅓"
        }
    }

    private var costLine: String {
        let tail = "Applies to the whole roll, not the frame — the solver has two degrees of freedom, not three, and can legitimately find none."
        guard let cost = roll.cost else { return "\(roll.medium.biasReason) \(tail)" }
        return "\(cost) \(tail)"
    }
}
