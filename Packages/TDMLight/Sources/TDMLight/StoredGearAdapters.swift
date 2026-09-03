import Foundation
import TDMCore

// The solver works in its own small gear types so the maths depends on nothing
// it does not use; these are the adapters at the edge, from what the app stores
// to what the solver needs. They live here rather than in the UI because they
// are pure and can be tested on Linux.

extension CameraBodyProfile {
    /// The solver's view of a stored body.
    ///
    /// The shutter mode is the caller's, not the body's: an M11 has 1/16000
    /// only once the photographer has switched the electronic shutter on, and
    /// the app must not solve against a ladder the camera is not set to.
    public init(_ body: CameraBody, shutterMode: ShutterMode = .standard) {
        self.init(
            name: body.name,
            shutterSpeeds: body.sortedShutterSpeeds,
            electronicShutterSpeeds: body.electronicShutterSpeeds.sorted(),
            mechanicalFallbackShutterSpeeds: body.mechanicalFallbackShutterSpeeds.sorted(),
            shutterMode: shutterMode,
            iso: ISOAvailability(body.iso),
            format: body.format,
            circleOfConfusionMillimetres: body.circleOfConfusionMillimetres,
            hasMeter: body.hasMeter,
            supportsAperturePriority: body.supportsAperturePriority
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
        case .aperturePriority: self = .aperturePriority
        }
    }

    /// The persisted form, dropping the motion.
    public var stored: StoredExposureStrategy {
        switch self {
        case .zoneFocus: .zoneFocus
        case .freezeMotion: .freezeMotion
        case .subjectIsolation: .subjectIsolation
        case .availableLight: .availableLight
        case .aperturePriority: .aperturePriority
        }
    }
}
