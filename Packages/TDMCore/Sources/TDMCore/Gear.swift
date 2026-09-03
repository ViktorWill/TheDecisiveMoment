import Foundation

/// What ISO a body can deliver.
///
/// Film is a real constraint rather than a nicety: the roll speed is fixed for
/// the whole roll, so the solver has one degree of freedom fewer.
public enum ISOMode: Sendable, Hashable, Codable {
    /// A loaded roll of film, at the speed it is rated at.
    case fixed(LoadedRoll)
    /// A sensor's usable range, in full stops from `minimum`, with the ceiling
    /// past which the user does not want the file, §7d.
    case range(minimum: Int, maximum: Int, ceiling: Int)

    /// A roll whose stock the photographer has not named — just a speed.
    public static func fixed(_ speed: Int) -> ISOMode {
        .fixed(LoadedRoll(speed: speed))
    }

    /// A sensor whose ceiling is its maximum: the user has not said where the
    /// file stops being worth having, so nothing is ruled out.
    public static func range(minimum: Int, maximum: Int) -> ISOMode {
        .range(minimum: minimum, maximum: maximum, ceiling: maximum)
    }

    /// The values a solver may choose from, ascending. The ceiling does not
    /// appear here — it is a preference, not a limit of the body — so
    /// ``solvableValues`` is what the solver enumerates.
    public var availableValues: [Int] {
        switch self {
        case let .fixed(roll):
            return roll.ratedAt > 0 ? [roll.ratedAt] : []
        case let .range(minimum, maximum, _):
            guard minimum > 0, maximum >= minimum else { return [] }
            var values: [Int] = []
            var value = Double(minimum)
            while Int(value.rounded()) <= maximum {
                values.append(Int(value.rounded()))
                value *= 2
            }
            return values.isEmpty ? [minimum] : values
        }
    }

    /// What the solver may actually choose: the ladder, capped at the ceiling.
    ///
    /// Empty when the ceiling sits below the body's slowest ISO, which the UI
    /// reports as a shortfall rather than quietly exceeding.
    public var solvableValues: [Int] {
        guard let ceiling else { return availableValues }
        return availableValues.filter { $0 <= ceiling }
    }

    /// The sensor's own limits, ceiling ignored — what raising the ceiling
    /// could reach. `nil` on film, where there is nothing to raise.
    public var sensorRange: (minimum: Int, maximum: Int)? {
        if case let .range(minimum, maximum, _) = self { return (minimum, maximum) }
        return nil
    }

    /// The user's ISO ceiling, `nil` on film.
    public var ceiling: Int? {
        if case let .range(_, _, ceiling) = self { return ceiling }
        return nil
    }

    /// What the light lands on, which sets the tolerance and the bias, §7a.
    public var medium: Medium {
        switch self {
        case let .fixed(roll): roll.medium
        case .range: .digital
        }
    }

    /// The loaded roll, `nil` on a digital body.
    public var loadedRoll: LoadedRoll? {
        if case let .fixed(roll) = self { return roll }
        return nil
    }

    public var isFilm: Bool {
        if case .fixed = self { return true }
        return false
    }

    // Hand-written so the persisted shape is `{"mode":"fixed","value":400}`
    // rather than the synthesised `{"fixed":{"_0":400}}`, which is unreadable in
    // a diff and awkward to write by hand in a seed profile. The film stock, the
    // rating and the ISO ceiling are written only where they say something the
    // speed does not, so an unnamed roll and an uncapped sensor keep the shape
    // they had before the roll was modelled.
    private enum CodingKeys: String, CodingKey {
        case mode, value, minimum, maximum, ceiling, stock, ratedAt
    }

    private enum Mode: String, Codable {
        case fixed, range
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .fixed:
            let boxSpeed = try container.decode(Int.self, forKey: .value)
            let stock = try container.decodeIfPresent(String.self, forKey: .stock)
                .flatMap(FilmStock.stock(id:)) ?? .unnamed(boxSpeed: boxSpeed)
            let ratedAt = try container.decodeIfPresent(Int.self, forKey: .ratedAt) ?? boxSpeed
            self = .fixed(LoadedRoll(stock: stock, ratedAt: ratedAt))
        case .range:
            let minimum = try container.decode(Int.self, forKey: .minimum)
            let maximum = try container.decode(Int.self, forKey: .maximum)
            self = .range(
                minimum: minimum,
                maximum: maximum,
                ceiling: try container.decodeIfPresent(Int.self, forKey: .ceiling) ?? maximum
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .fixed(roll):
            try container.encode(Mode.fixed, forKey: .mode)
            try container.encode(roll.stock.boxSpeed, forKey: .value)
            if roll.stock.isNamed {
                try container.encode(roll.stock.id, forKey: .stock)
            }
            if roll.ratedAt != roll.stock.boxSpeed {
                try container.encode(roll.ratedAt, forKey: .ratedAt)
            }
        case let .range(minimum, maximum, ceiling):
            try container.encode(Mode.range, forKey: .mode)
            try container.encode(minimum, forKey: .minimum)
            try container.encode(maximum, forKey: .maximum)
            if ceiling != maximum {
                try container.encode(ceiling, forKey: .ceiling)
            }
        }
    }
}

/// What the photographer is trying to do, `docs/SPEC-light.md`.
///
/// `TDMLight.ExposureStrategy` is the solver-facing variant and carries the
/// subject motion with `freezeMotion`; this one is the persisted preference, so
/// it stays a plain string in storage and callers adapt at the edge.
public enum ExposureStrategy: String, Sendable, Codable, CaseIterable, Hashable {
    case zoneFocus
    case freezeMotion
    case subjectIsolation
    case availableLight
    /// Pick the aperture and let the body choose a stepless shutter. Only an M7
    /// has this, so it is offered only where ``CameraBody/supportsAperturePriority``
    /// says so — see ``availableStrategies(on:)``.
    case aperturePriority

    /// Whether a body can actually be set this way.
    public func isAvailable(on body: CameraBody) -> Bool {
        self != .aperturePriority || body.supportsAperturePriority
    }

    /// The strategies worth offering for a body, in the order the UI shows them.
    public static func availableStrategies(on body: CameraBody) -> [ExposureStrategy] {
        allCases.filter { $0.isAvailable(on: body) }
    }
}

/// `ExposureStrategy` under a name that does not collide.
///
/// `TDMCore` names both this module and an enum inside it, so qualifying this
/// type by module is ambiguous wherever `TDMLight`'s solver-facing enum of the
/// same name is also in scope. Use this alias there, as `SpotSourceKind` is used
/// for `SpotSource`.
public typealias StoredExposureStrategy = ExposureStrategy

/// A body, as the app stores it.
public struct CameraBody: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// The real shutter ladder, in seconds: `1/250`, never `250`.
    public var shutterSpeeds: [TimeInterval]
    /// Speeds the body has only with its electronic shutter switched on — the
    /// M11's 1/8000 and 1/16000, and nothing on any other M.
    ///
    /// Kept apart from ``shutterSpeeds`` because it is a mode the photographer
    /// has to remember to select, and because f/2 in bright sun is reachable on
    /// exactly this ladder and on no other, `docs/EXPOSURE-MODEL.md` §7b.
    public var electronicShutterSpeeds: [TimeInterval]
    /// What is left when the battery is flat. An M7 keeps 1/60 and 1/125
    /// mechanically; a fully mechanical M keeps everything, and an M with a dead
    /// battery and no mechanical speeds keeps nothing — both are the empty case
    /// here, since there is no fallback to switch to.
    public var mechanicalFallbackShutterSpeeds: [TimeInterval]
    public var iso: ISOMode
    /// The frame this body draws, which is where its circle of confusion comes
    /// from. Full frame everywhere except the M8.
    public var format: SensorFormat
    /// Circle of confusion for the format, millimetres. Defaults to the
    /// format's own figure — 0.030 mm full frame, 0.0225 mm APS-H — and is
    /// settable for the stricter 0.025 mm standard.
    public var circleOfConfusionMillimetres: Double
    /// Whether the body meters at all — an M-A does not, and the app is the
    /// meter in that case.
    public var hasMeter: Bool
    /// Whether the body will pick the shutter itself. True on an M7 and nothing
    /// else in the roster.
    public var supportsAperturePriority: Bool
    /// What is loaded, when the roll is not one of the catalogue stocks. The
    /// roll itself — stock, medium and rating — travels in ``iso``; this is the
    /// free-text name for a roll the catalogue has not got.
    public var loadedFilm: String?

    public init(
        id: UUID = UUID(),
        name: String,
        shutterSpeeds: [TimeInterval],
        electronicShutterSpeeds: [TimeInterval] = [],
        mechanicalFallbackShutterSpeeds: [TimeInterval] = [],
        iso: ISOMode,
        format: SensorFormat = .fullFrame,
        circleOfConfusionMillimetres: Double? = nil,
        hasMeter: Bool = true,
        supportsAperturePriority: Bool = false,
        loadedFilm: String? = nil
    ) {
        self.id = id
        self.name = name
        self.shutterSpeeds = shutterSpeeds
        self.electronicShutterSpeeds = electronicShutterSpeeds
        self.mechanicalFallbackShutterSpeeds = mechanicalFallbackShutterSpeeds
        self.iso = iso
        self.format = format
        self.circleOfConfusionMillimetres = circleOfConfusionMillimetres
            ?? format.circleOfConfusionMillimetres
        self.hasMeter = hasMeter
        self.supportsAperturePriority = supportsAperturePriority
        self.loadedFilm = loadedFilm
    }

    // Written by hand so a profile stored before the roster grew still decodes:
    // a body with no format is full frame, a body with no electronic ladder has
    // no electronic shutter, and a body that says nothing about aperture
    // priority has not got it.
    private enum CodingKeys: String, CodingKey {
        case id, name, shutterSpeeds, electronicShutterSpeeds, mechanicalFallbackShutterSpeeds
        case iso, format, circleOfConfusionMillimetres, hasMeter, supportsAperturePriority, loadedFilm
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decodeIfPresent(SensorFormat.self, forKey: .format) ?? .fullFrame
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            shutterSpeeds: try container.decode([TimeInterval].self, forKey: .shutterSpeeds),
            electronicShutterSpeeds: try container.decodeIfPresent(
                [TimeInterval].self, forKey: .electronicShutterSpeeds
            ) ?? [],
            mechanicalFallbackShutterSpeeds: try container.decodeIfPresent(
                [TimeInterval].self, forKey: .mechanicalFallbackShutterSpeeds
            ) ?? [],
            iso: try container.decode(ISOMode.self, forKey: .iso),
            format: format,
            circleOfConfusionMillimetres: try container.decodeIfPresent(
                Double.self, forKey: .circleOfConfusionMillimetres
            ),
            hasMeter: try container.decodeIfPresent(Bool.self, forKey: .hasMeter) ?? true,
            supportsAperturePriority: try container.decodeIfPresent(
                Bool.self, forKey: .supportsAperturePriority
            ) ?? false,
            loadedFilm: try container.decodeIfPresent(String.self, forKey: .loadedFilm)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(shutterSpeeds, forKey: .shutterSpeeds)
        if !electronicShutterSpeeds.isEmpty {
            try container.encode(electronicShutterSpeeds, forKey: .electronicShutterSpeeds)
        }
        if !mechanicalFallbackShutterSpeeds.isEmpty {
            try container.encode(mechanicalFallbackShutterSpeeds, forKey: .mechanicalFallbackShutterSpeeds)
        }
        try container.encode(iso, forKey: .iso)
        try container.encode(format, forKey: .format)
        try container.encode(circleOfConfusionMillimetres, forKey: .circleOfConfusionMillimetres)
        try container.encode(hasMeter, forKey: .hasMeter)
        if supportsAperturePriority {
            try container.encode(supportsAperturePriority, forKey: .supportsAperturePriority)
        }
        try container.encodeIfPresent(loadedFilm, forKey: .loadedFilm)
    }

    /// Ascending, which is the order every ladder-walking algorithm assumes.
    public var sortedShutterSpeeds: [TimeInterval] { shutterSpeeds.sorted() }

    /// The dial plus whatever the electronic shutter adds, ascending.
    public var allShutterSpeeds: [TimeInterval] {
        Set(shutterSpeeds + electronicShutterSpeeds).sorted()
    }

    public var hasElectronicShutter: Bool { !electronicShutterSpeeds.isEmpty }

    /// What the light lands on: the loaded roll's medium, or digital raw.
    public var medium: Medium { iso.medium }

    /// The loaded roll, `nil` on a digital body.
    public var loadedRoll: LoadedRoll? { iso.loadedRoll }

    /// How the ISO reads on screen: `HP5 400 @ 1600 (+2)` on film, `ISO 1600`
    /// on a sensor. On film the rating is shown wherever the ISO appears, §7c.
    public var isoDescription: String {
        if let roll = loadedRoll {
            return roll.stock.isNamed ? roll.displayName : "ISO \(roll.ratedAt)"
        }
        return "ISO \(iso.availableValues.first ?? 100)"
    }

    /// The fastest speed on the dial, seconds. `1/1000` on an M6.
    public var fastestShutter: TimeInterval? { shutterSpeeds.filter { $0 > 0 }.min() }

    /// The fastest speed the body has in any mode, seconds — 1/16000 on an M11.
    public var fastestShutterInAnyMode: TimeInterval? { allShutterSpeeds.filter { $0 > 0 }.min() }

    public var isValid: Bool {
        !name.isEmpty
            && !shutterSpeeds.isEmpty
            && shutterSpeeds.allSatisfy { $0 > 0 && $0.isFinite }
            && electronicShutterSpeeds.allSatisfy { $0 > 0 && $0.isFinite }
            && mechanicalFallbackShutterSpeeds.allSatisfy { $0 > 0 && $0.isFinite }
            && !iso.availableValues.isEmpty
            && circleOfConfusionMillimetres > 0
    }
}

/// A lens, as the app stores it. Lengths in millimetres, distances in metres.
public struct Lens: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var focalLengthMillimetres: Double
    /// The real click stops, as f-numbers.
    public var apertures: [Double]
    /// The marks engraved on the barrel, metres. `.infinity` is a legitimate
    /// entry. The whole output is "set the barrel to *this* mark", so a mark the
    /// lens does not have makes the advice unusable.
    public var distanceMarksMetres: [Double]
    public var minimumFocusMetres: Double

    public init(
        id: UUID = UUID(),
        name: String,
        focalLengthMillimetres: Double,
        apertures: [Double],
        distanceMarksMetres: [Double],
        minimumFocusMetres: Double
    ) {
        self.id = id
        self.name = name
        self.focalLengthMillimetres = focalLengthMillimetres
        self.apertures = apertures
        self.distanceMarksMetres = distanceMarksMetres
        self.minimumFocusMetres = minimumFocusMetres
    }

    public var sortedApertures: [Double] { apertures.sorted() }
    public var sortedDistanceMarks: [Double] { distanceMarksMetres.sorted() }
    public var widestAperture: Double? { apertures.min() }

    public var isValid: Bool {
        !name.isEmpty
            && focalLengthMillimetres > 0
            && !apertures.isEmpty && apertures.allSatisfy { $0 > 0 && $0.isFinite }
            && !distanceMarksMetres.isEmpty && distanceMarksMetres.allSatisfy { $0 > 0 }
            && minimumFocusMetres > 0
    }

    // JSON has no infinity, and the ∞ mark is engraved on every one of these
    // lenses, so it travels as a flag beside the finite marks rather than as a
    // sentinel number a future reader would have to guess at.
    private enum CodingKeys: String, CodingKey {
        case id, name, focalLengthMillimetres, apertures, distanceMarksMetres
        case hasInfinityMark, minimumFocusMetres
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        focalLengthMillimetres = try container.decode(Double.self, forKey: .focalLengthMillimetres)
        apertures = try container.decode([Double].self, forKey: .apertures)
        minimumFocusMetres = try container.decode(Double.self, forKey: .minimumFocusMetres)

        var marks = try container.decode([Double].self, forKey: .distanceMarksMetres)
        if try container.decodeIfPresent(Bool.self, forKey: .hasInfinityMark) ?? false {
            marks.append(.infinity)
        }
        distanceMarksMetres = marks
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(focalLengthMillimetres, forKey: .focalLengthMillimetres)
        try container.encode(apertures, forKey: .apertures)
        try container.encode(distanceMarksMetres.filter(\.isFinite), forKey: .distanceMarksMetres)
        try container.encode(distanceMarksMetres.contains { !$0.isFinite }, forKey: .hasInfinityMark)
        try container.encode(minimumFocusMetres, forKey: .minimumFocusMetres)
    }
}

/// A body, a lens and how this photographer works — set once, changed rarely.
public struct GearProfile: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var body: CameraBody
    public var lens: Lens
    public var strategy: ExposureStrategy
    /// Measured difference between this body's meter and the model, in stops.
    /// Added to the estimate before solving.
    public var calibrationOffsetEV: Double

    public init(
        id: UUID = UUID(),
        name: String,
        body: CameraBody,
        lens: Lens,
        strategy: ExposureStrategy = .zoneFocus,
        calibrationOffsetEV: Double = 0
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.lens = lens
        self.strategy = strategy
        self.calibrationOffsetEV = calibrationOffsetEV
    }

    /// "M6 · 35mm" — the summary shown on a session, and a conversation
    /// starter rather than a spec sheet.
    public var summary: String {
        "\(body.name) · \(Int(lens.focalLengthMillimetres.rounded()))mm"
    }

    public var isValid: Bool {
        !name.isEmpty && body.isValid && lens.isValid && abs(calibrationOffsetEV) <= 3
    }
}
