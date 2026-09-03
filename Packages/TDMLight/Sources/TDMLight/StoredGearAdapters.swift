import Foundation
import TDMCore

// The solver works in its own small gear types so the maths depends on nothing
// it does not use; these are the adapters at the edge, from what the app stores
// to what the solver needs. They live here rather than in the UI because they
// are pure and can be tested on Linux.

extension CameraBodyProfile {
    /// The solver's view of a stored body.
    public init(_ body: CameraBody) {
        self.init(
            name: body.name,
            shutterSpeeds: body.sortedShutterSpeeds,
            iso: ISOAvailability(body.iso),
            circleOfConfusionMillimetres: body.circleOfConfusionMillimetres
        )
    }
}

extension ISOAvailability {
    public init(_ mode: ISOMode) {
        switch mode {
        case let .fixed(roll): self = .fixed(roll)
        case let .range(minimum, maximum, ceiling):
            self = .range(minimum: minimum, maximum: maximum, ceiling: ceiling)
        }
    }
}

extension LensProfile {
    /// The solver's view of a stored lens. The engraved marks travel unchanged —
    /// including `∞` — because the recommendation is one of them.
    public init(_ lens: Lens) {
        self.init(
            name: lens.name,
            focalLengthMillimetres: lens.focalLengthMillimetres,
            apertures: lens.sortedApertures,
            distanceMarksMetres: lens.sortedDistanceMarks,
            minimumFocusMetres: lens.minimumFocusMetres
        )
    }
}

extension ExposureStrategy {
    /// The stored preference, given the motion the freeze strategy needs and the
    /// stored strategy does not carry.
    public init(_ strategy: StoredExposureStrategy, motion: SubjectMotion = .walking) {
        switch strategy {
        case .zoneFocus: self = .zoneFocus
        case .freezeMotion: self = .freezeMotion(motion)
        case .subjectIsolation: self = .subjectIsolation
        case .availableLight: self = .availableLight
        }
    }

    /// The persisted form, dropping the motion.
    public var stored: StoredExposureStrategy {
        switch self {
        case .zoneFocus: .zoneFocus
        case .freezeMotion: .freezeMotion
        case .subjectIsolation: .subjectIsolation
        case .availableLight: .availableLight
        }
    }
}
