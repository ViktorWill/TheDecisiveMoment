import Foundation

/// The ISO a body can actually deliver.
///
/// Film mode is a real constraint, not a nicety: the roll speed is fixed for the
/// whole roll, so the solver has one fewer degree of freedom.
public enum ISOAvailability: Sendable, Equatable {
    /// A loaded roll of film.
    case fixed(Int)
    /// A digital sensor's usable range, enumerated in full stops from `minimum`.
    case range(minimum: Int, maximum: Int)

    /// The ISO values the solver may choose from.
    public var availableValues: [Int] {
        switch self {
        case let .fixed(value):
            return [value]
        case let .range(minimum, maximum):
            guard minimum > 0, maximum >= minimum else { return [] }
            var values: [Int] = []
            var value = Double(minimum)
            while Int(value.rounded()) <= maximum {
                values.append(Int(value.rounded()))
                value *= 2
            }
            if values.isEmpty { values = [minimum] }
            return values
        }
    }
}

/// A body, as far as the exposure solver is concerned.
///
/// `TDMCore` gains the richer `CameraBody` value type in M2; this is the subset
/// the maths needs, so `TDMLight` stays free of anything it does not use.
public struct CameraBodyProfile: Sendable, Equatable {
    public var name: String
    /// The body's real shutter ladder, in seconds. `1/250`, never `250`.
    public var shutterSpeeds: [TimeInterval]
    public var iso: ISOAvailability
    /// Circle of confusion for the format, millimetres. 0.030 mm for full frame.
    public var circleOfConfusionMillimetres: Double

    public init(
        name: String,
        shutterSpeeds: [TimeInterval],
        iso: ISOAvailability,
        circleOfConfusionMillimetres: Double = DepthOfField.fullFrameCircleOfConfusionMillimetres
    ) {
        self.name = name
        self.shutterSpeeds = shutterSpeeds
        self.iso = iso
        self.circleOfConfusionMillimetres = circleOfConfusionMillimetres
    }
}

/// A lens, as far as the exposure and zone-focus maths are concerned.
public struct LensProfile: Sendable, Equatable {
    public var name: String
    public var focalLengthMillimetres: Double
    /// The lens's real aperture stops, as f-numbers.
    public var apertures: [Double]
    /// The distances engraved on the barrel, metres, ascending. `.infinity` is a
    /// legitimate entry. Never recommend a distance that is not in this list.
    public var distanceMarksMetres: [Double]
    /// Minimum focus, metres.
    public var minimumFocusMetres: Double

    public init(
        name: String,
        focalLengthMillimetres: Double,
        apertures: [Double],
        distanceMarksMetres: [Double],
        minimumFocusMetres: Double
    ) {
        self.name = name
        self.focalLengthMillimetres = focalLengthMillimetres
        self.apertures = apertures
        self.distanceMarksMetres = distanceMarksMetres
        self.minimumFocusMetres = minimumFocusMetres
    }

    /// The engraved marks in ascending order.
    public var sortedDistanceMarks: [Double] { distanceMarksMetres.sorted() }
}
