import Foundation

/// What ISO a body can deliver.
///
/// Film is a real constraint rather than a nicety: the roll speed is fixed for
/// the whole roll, so the solver has one degree of freedom fewer.
public enum ISOMode: Sendable, Hashable, Codable {
    /// A loaded roll of film.
    case fixed(Int)
    /// A sensor's usable range, in full stops from `minimum`.
    case range(minimum: Int, maximum: Int)

    /// The values a solver may choose from, ascending.
    public var availableValues: [Int] {
        switch self {
        case let .fixed(value):
            return value > 0 ? [value] : []
        case let .range(minimum, maximum):
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

    public var isFilm: Bool {
        if case .fixed = self { return true }
        return false
    }

    // Hand-written so the persisted shape is `{"mode":"fixed","value":400}`
    // rather than the synthesised `{"fixed":{"_0":400}}`, which is unreadable in
    // a diff and awkward to write by hand in a seed profile.
    private enum CodingKeys: String, CodingKey {
        case mode, value, minimum, maximum
    }

    private enum Mode: String, Codable {
        case fixed, range
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .fixed:
            self = .fixed(try container.decode(Int.self, forKey: .value))
        case .range:
            self = .range(
                minimum: try container.decode(Int.self, forKey: .minimum),
                maximum: try container.decode(Int.self, forKey: .maximum)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .fixed(value):
            try container.encode(Mode.fixed, forKey: .mode)
            try container.encode(value, forKey: .value)
        case let .range(minimum, maximum):
            try container.encode(Mode.range, forKey: .mode)
            try container.encode(minimum, forKey: .minimum)
            try container.encode(maximum, forKey: .maximum)
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
    public var iso: ISOMode
    /// Circle of confusion for the format, millimetres. 0.030 mm full frame.
    public var circleOfConfusionMillimetres: Double
    /// Whether the body meters at all — an M4 does not, and the app is the
    /// meter in that case.
    public var hasMeter: Bool
    /// What is loaded, when film is loaded. Set once when the roll goes in.
    public var loadedFilm: String?

    public init(
        id: UUID = UUID(),
        name: String,
        shutterSpeeds: [TimeInterval],
        iso: ISOMode,
        circleOfConfusionMillimetres: Double = 0.030,
        hasMeter: Bool = true,
        loadedFilm: String? = nil
    ) {
        self.id = id
        self.name = name
        self.shutterSpeeds = shutterSpeeds
        self.iso = iso
        self.circleOfConfusionMillimetres = circleOfConfusionMillimetres
        self.hasMeter = hasMeter
        self.loadedFilm = loadedFilm
    }

    /// Ascending, which is the order every ladder-walking algorithm assumes.
    public var sortedShutterSpeeds: [TimeInterval] { shutterSpeeds.sorted() }

    public var isValid: Bool {
        !name.isEmpty
            && !shutterSpeeds.isEmpty
            && shutterSpeeds.allSatisfy { $0 > 0 && $0.isFinite }
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
