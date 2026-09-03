import Foundation

/// What the light lands on, `docs/EXPOSURE-MODEL.md` §7a.
///
/// The medium is not a label: it sets how far off a candidate setting may be
/// before it is discarded, and where inside that band the solver aims. A stop
/// over on HP5 is a usable negative; the same stop on Provia is gone.
public enum Medium: String, Sendable, Hashable, Codable, CaseIterable {
    case blackAndWhiteNegative
    case colourNegative
    case slide
    case digital

    /// How far a candidate may sit from the aim before it is a discard, §7a.
    public var latitude: Latitude {
        switch self {
        case .blackAndWhiteNegative: Latitude(overStops: 3.0, underStops: 1.0)
        case .colourNegative: Latitude(overStops: 3.0, underStops: 1.0)
        case .slide: Latitude(overStops: 0.5, underStops: 1.0)
        case .digital: Latitude(overStops: 1.0, underStops: 2.0)
        }
    }

    /// Where inside the band the solver aims, in stops: `EV_target = EV_scene −
    /// bias`. Positive means *more* light than a meter would give, which is what
    /// negative film wants.
    public var biasEV: Double {
        switch self {
        case .blackAndWhiteNegative: 1.0 / 3
        case .colourNegative: 2.0 / 3
        case .slide: -1.0 / 3
        case .digital: -1.0 / 3
        }
    }

    /// Everything but a sensor: the ISO is a property of the loaded roll.
    public var isFilm: Bool { self != .digital }

    /// As it reads on the gear screen.
    public var displayName: String {
        switch self {
        case .blackAndWhiteNegative: "B&W negative"
        case .colourNegative: "Colour negative"
        case .slide: "Slide"
        case .digital: "Digital raw"
        }
    }

    /// The one sentence §7a gives for why this medium is biased the way it is.
    public var biasReason: String {
        switch self {
        case .blackAndWhiteNegative: "Expose for the shadows; highlights hold on."
        case .colourNegative: "Rated conservatively; +1 is common practice."
        case .slide: "No highlight recovery at all. Protect the highlights."
        case .digital: "Clipped highlights are gone; shadows lift."
        }
    }
}

/// How much exposure error a medium survives, in stops, either side of the aim.
///
/// Asymmetric on purpose. Both numbers are magnitudes: `overStops` is how much
/// *more* light than the aim the medium takes, `underStops` how much less.
public struct Latitude: Sendable, Hashable, Codable {
    public let overStops: Double
    public let underStops: Double

    public init(overStops: Double, underStops: Double) {
        self.overStops = overStops
        self.underStops = underStops
    }

    /// Whether a candidate this far from the aim is still a negative worth
    /// having.
    ///
    /// - Parameter errorStops: Signed, in the solver's convention: negative is
    ///   more light than the aim (over-exposed), positive is less (under).
    public func accepts(errorStops: Double) -> Bool {
        errorStops <= underStops + 1e-9 && -errorStops <= overStops + 1e-9
    }

    /// `+3 / −1`, as the gear screen prints it.
    public var summary: String {
        "+\(Latitude.number(overStops)) / −\(Latitude.number(underStops))"
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// A film stock, as the app knows it.
///
/// `boxSpeed` is what the carton says; what the roll is *rated* at is a decision
/// the photographer makes when it goes in, and lives on ``LoadedRoll``.
public struct FilmStock: Sendable, Hashable, Codable, Identifiable {
    /// A stable slug, so a stored roll survives a rename of the printed name.
    public let id: String
    public let name: String
    public let boxSpeed: Int
    public let medium: Medium
    /// Why a photographer reaches for it. Shown under the picker.
    public let note: String

    public init(id: String, name: String, boxSpeed: Int, medium: Medium, note: String) {
        self.id = id
        self.name = name
        self.boxSpeed = boxSpeed
        self.medium = medium
        self.note = note
    }

    /// `HP5 400`. An unnamed roll is only ever a speed, so it does not repeat
    /// it: `ISO 400`.
    public var shortName: String { isNamed ? "\(shortLabel) \(boxSpeed)" : name }

    /// The name without the manufacturer, which is what a photographer says out
    /// loud and all the room a readout has.
    public var shortLabel: String {
        switch id {
        case "hp5": "HP5"
        case "trix": "Tri-X"
        case "fp4": "FP4"
        case "delta3200": "Delta"
        case "portra400": "Portra"
        case "ektar100": "Ektar"
        case "provia100f": "Provia"
        case "velvia50": "Velvia"
        default: name
        }
    }

    /// The seed catalogue, `docs/SPEC-light.md`. Eight stocks that between them
    /// cover the street: four black and white, two colour negative, two slide.
    public static let catalogue: [FilmStock] = [
        FilmStock(
            id: "hp5",
            name: "Ilford HP5 Plus",
            boxSpeed: 400,
            medium: .blackAndWhiteNegative,
            note: "The street default. Pushes to 1600 without complaint."
        ),
        FilmStock(
            id: "trix",
            name: "Kodak Tri-X 400",
            boxSpeed: 400,
            medium: .blackAndWhiteNegative,
            note: "More contrast than HP5, and the grain is the point."
        ),
        FilmStock(
            id: "fp4",
            name: "Ilford FP4 Plus",
            boxSpeed: 125,
            medium: .blackAndWhiteNegative,
            note: "Fine grain for bright days; too slow for a shaded street."
        ),
        FilmStock(
            id: "delta3200",
            name: "Ilford Delta 3200",
            boxSpeed: 3200,
            medium: .blackAndWhiteNegative,
            note: "Nominally 3200; the true speed is nearer 1000, so it is already a push."
        ),
        FilmStock(
            id: "portra400",
            name: "Kodak Portra 400",
            boxSpeed: 400,
            medium: .colourNegative,
            note: "Rated conservatively — a stop over is the house style."
        ),
        FilmStock(
            id: "ektar100",
            name: "Kodak Ektar 100",
            boxSpeed: 100,
            medium: .colourNegative,
            note: "Saturated and slow. Sunlight only."
        ),
        FilmStock(
            id: "provia100f",
            name: "Fujifilm Provia 100F",
            boxSpeed: 100,
            medium: .slide,
            note: "Slide: no highlight recovery. Meter it or lose it."
        ),
        FilmStock(
            id: "velvia50",
            name: "Fujifilm Velvia 50",
            boxSpeed: 50,
            medium: .slide,
            note: "Half a stop of latitude and colour like nothing else."
        ),
    ]

    public static func stock(id: String) -> FilmStock? {
        catalogue.first { $0.id == id }
    }

    /// A roll whose stock the photographer has not named — an M6 that only knows
    /// the speed dialled on the back. Black and white negative is the assumption
    /// the street makes, and §7a's most forgiving row, so it never invents
    /// latitude the roll has not got.
    public static func unnamed(boxSpeed: Int) -> FilmStock {
        FilmStock(
            id: "unnamed-\(boxSpeed)",
            name: "ISO \(boxSpeed)",
            boxSpeed: boxSpeed,
            medium: .blackAndWhiteNegative,
            note: "No stock chosen — treated as black and white negative."
        )
    }

    public var isNamed: Bool { !id.hasPrefix("unnamed-") }
}

/// What is actually in the camera: a stock, and the speed it is rated at.
///
/// Rating is a whole-roll decision, made once when the roll goes in, and the app
/// shows it wherever the ISO appears — `HP5 400 @ 1600 (+2)`, §7c.
public struct LoadedRoll: Sendable, Hashable, Codable {
    public var stock: FilmStock
    /// The speed the roll is being exposed at. Box speed unless pushed or pulled.
    public var ratedAt: Int

    public init(stock: FilmStock, ratedAt: Int? = nil) {
        self.stock = stock
        self.ratedAt = ratedAt ?? stock.boxSpeed
    }

    /// A plain roll of unnamed film at a dialled-in speed.
    public init(speed: Int) {
        self.init(stock: .unnamed(boxSpeed: speed), ratedAt: speed)
    }

    public var medium: Medium { stock.medium }

    /// Stops away from box speed. `+2` for HP5 400 at 1600, `−1` for a pull.
    ///
    /// Fractional in principle — a roll rated at 320 is −0.32 stops — so this is
    /// a `Double` and the whole-stop ratings are just the ones the UI offers.
    public var pushStops: Double {
        guard stock.boxSpeed > 0, ratedAt > 0 else { return 0 }
        return log2(Double(ratedAt) / Double(stock.boxSpeed))
    }

    public var isPushed: Bool { pushStops > 0.01 }
    public var isPulled: Bool { pushStops < -0.01 }

    /// `HP5 400 @ 1600 (+2)`, or just `HP5 400` at box speed.
    public var displayName: String {
        guard isPushed || isPulled else { return stock.shortName }
        return "\(stock.shortName) @ \(ratedAt) (\(signedStops))"
    }

    /// `+2`, `−1`, `+1⅓`.
    public var signedStops: String {
        let sign = pushStops < 0 ? "−" : "+"
        let magnitude = abs(pushStops)
        let whole = magnitude.rounded()
        let text = abs(magnitude - whole) < 0.02
            ? String(Int(whole))
            : String(format: "%.1f", magnitude)
        return sign + text
    }

    /// What the push costs, §7c. The cost is stated wherever the rating is.
    public var cost: String? {
        switch Int(pushStops.rounded()) {
        case ..<0: "Flat negatives, finer grain — rarely worth it in the street."
        case 0: nil
        case 1: "Slightly more contrast and grain."
        case 2: "Coarse grain, blocked shadows."
        default: "Heavy grain, shadows gone — a look, not a fix."
        }
    }

    /// The ratings the UI offers: one stop of pull, three of push, §7c.
    public var availableRatings: [Int] {
        Self.pushRange.map { Int((Double(stock.boxSpeed) * pow(2, Double($0))).rounded()) }
    }

    /// Pull one, box, push up to three. Past +3 the shadows are gone and it is
    /// no longer a fix.
    public static let pushRange = -1...3
}
