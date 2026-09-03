import SwiftUI
import TDMCore

/// The Map tab's tokens, lifted from `design/Tokens.dc.html`, `design/Map.dc.html`
/// and `design/SpotDetail.dc.html`.
///
/// The map canvas is a *darker* ground than the rest of the app — #0B0C0E
/// against #101113 — so that markers separate from it. Everything drawn over
/// tiles is measured against that ground, which is why these live here rather
/// than in ``LightTheme``.
enum MapTheme {
    /// The map canvas, #0B0C0E. Darker than the app background on purpose.
    static let ground = Color(hex: 0x0B0C0E)
    /// The app page, #101113. Also the ink of anything drawn on the accent.
    static let background = Color(hex: 0x101113)
    /// The sheet over the map, #141518.
    static let sheet = Color(hex: 0x141518)
    /// A control on the sheet, #1E2126.
    static let control = Color(hex: 0x1E2126)
    /// The search field's well, #0E0F11.
    static let field = Color(hex: 0x0E0F11)
    /// A photo tile's plate, #1C1F24.
    static let plate = Color(hex: 0x1C1F24)
    static let hairline = Color(hex: 0x2A2E34)
    /// The lighter rule between list rows, #22262B.
    static let rowRule = Color(hex: 0x22262B)
    static let primaryText = Color(hex: 0xEDEDEA)
    /// Body copy in the note, #C8CBCF.
    static let bodyText = Color(hex: 0xC8CBCF)
    static let secondaryText = Color(hex: 0x9A9DA3)
    static let tertiaryText = Color(hex: 0x62666C)
    /// Photo credits and axis ticks, #4E5257. The quietest legible ink.
    static let quaternaryText = Color(hex: 0x4E5257)
    static let accent = Color(hex: 0xE8A64A)
    /// Curated: hand-written entries, and the markers that draw over the rest.
    static let curated = Color(hex: 0xC4392F)
    /// A generated marker, #4B5563.
    static let marker = Color(hex: 0x4B5563)
    /// A low-scoring marker, #3E444C — a dot with no glyph.
    static let markerFaint = Color(hex: 0x3E444C)
    /// The dot inside a faint marker, #B9BCC0.
    static let markerDot = Color(hex: 0xB9BCC0)
    /// A marker glyph, #D4D6D9.
    static let glyph = Color(hex: 0xD4D6D9)
    /// The cluster bubble, #191B1E over #3E444C.
    static let clusterFill = Color(hex: 0x191B1E)
    static let clusterStroke = Color(hex: 0x3E444C)
    /// The offline badge, #6E9B5C. Green because it is good news: the city is
    /// on the device.
    static let offline = Color(hex: 0x6E9B5C)
    /// An unlit bar of the best-hours strip, #262A30.
    static let barOff = Color(hex: 0x262A30)
    /// The sheet's grab handle, #3A3F46.
    static let handle = Color(hex: 0x3A3F46)

    /// Chips and floating buttons sit on tiles, so they carry the page colour
    /// at 92% rather than a blur that would wash out at night.
    static let floating = Color(hex: 0x101113).opacity(0.92)

    // MARK: Type

    /// A row title, 14 / 600.
    static let rowTitleFont = Font.system(size: 14, weight: .semibold)
    /// A row's prose score, 11 / 400.
    static let rowDetailFont = Font.system(size: 11)
    /// A distance, 11 / 400 tabular.
    static let rowDistanceFont = Font.system(size: 11).monospacedDigit()
    /// The city chip's name, 13 / 600.
    static let chipFont = Font.system(size: 13, weight: .semibold)
    /// The city chip's count, mono 11.
    static let chipCountFont = Font.system(size: 11).monospacedDigit()
    /// The OFFLINE badge, mono 9 / 600 at 0.08 em.
    static let badgeFont = Font.system(size: 9, weight: .semibold).monospacedDigit()
    /// A filter pill, 12 / 500.
    static let pillFont = Font.system(size: 12, weight: .medium)
    /// A section label, 10 / 600 at 0.12 em, upper case.
    static let sectionLabelFont = Font.system(size: 10, weight: .semibold)
    /// The detail sheet's title, 21 / 600.
    static let titleFont = Font.system(size: 21, weight: .semibold)
    /// The detail sheet's distance, mono 15.
    static let distanceFont = Font.system(size: 15).monospacedDigit()
    /// A setting in the light strip, mono 22 / 500.
    static let settingFont = Font.system(size: 22, weight: .medium).monospacedDigit()
    /// The ISO beside it, mono 15.
    static let settingSecondaryFont = Font.system(size: 15).monospacedDigit()
    /// The note, 14 pt.
    static let noteFont = Font.system(size: 14)
    /// A caption: photo credits, hour ticks. 9 pt.
    static let creditFont = Font.system(size: 9)
    static let tickFont = Font.system(size: 9).monospacedDigit()

    // MARK: Metrics

    /// The screen gutter, 20 pt.
    static let gutter: CGFloat = 20
    /// Chips, buttons and badges: 8, 6 and 3 pt radii.
    static let chipRadius: CGFloat = 8
    static let tileRadius: CGFloat = 6
    static let badgeRadius: CGFloat = 3
    /// A filter pill: 32 pt tall, fully rounded at 16.
    static let pillHeight: CGFloat = 32
    static let searchFieldHeight: CGFloat = 40
    /// The detail sheet's action row, 46 pt.
    static let actionHeight: CGFloat = 46
    /// The floating buttons, 44 pt — the minimum comfortable target.
    static let floatingSize: CGFloat = 44

    // MARK: Markers

    /// A marker's radius in points, from its score: 10 at 0, 17 at 1, which are
    /// the smallest and largest circles in `design/Map.dc.html`.
    static func markerRadius(score: Double) -> CGFloat {
        let clamped = min(max(score, 0), 1)
        return 10 + 7 * CGFloat(clamped)
    }

    /// Opacity by score. Never below 0.65: a marker that cannot be seen is a
    /// spot that does not exist.
    static func markerOpacity(score: Double) -> Double {
        0.65 + 0.35 * min(max(score, 0), 1)
    }

    /// Below this radius the glyph would be illegible, and the marker becomes
    /// the plain dot the mockup draws for its weakest spots.
    static let glyphThresholdRadius: CGFloat = 12

    /// The fill of a marker: curated red, or the grey that darkens as the score
    /// falls.
    static func markerFill(score: Double, curated: Bool) -> Color {
        if curated { return MapTheme.curated }
        return score < 0.35 ? markerFaint : marker
    }

    /// SF Symbols by kind, `docs/SPEC-map.md` ("Annotations").
    static func symbol(for kind: SpotKind) -> String {
        switch kind {
        case .plaza: "building.columns"
        case .market: "cart"
        case .street: "figure.walk"
        case .bridge: "road.lanes"
        case .stairs: "stairs"
        case .underpass: "arrow.down.forward.and.arrow.up.backward"
        case .arcade: "building.2"
        case .transit: "tram"
        case .waterfront: "water.waves"
        case .park: "tree"
        case .viewpoint: "binoculars"
        case .intersection: "arrow.triangle.branch"
        case .landmark: "mappin.and.ellipse"
        case .other: "mappin"
        }
    }
}

extension Color {
    /// The design files quote hex, so the code does too — a token typed as
    /// three decimals is a token nobody can diff against `design/`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
