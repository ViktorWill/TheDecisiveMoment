#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore

/// A stored camera body.
///
/// SwiftData holds primitives and lets the value types in `TDMCore` stay the
/// currency between layers: every model here converts both ways, and nothing
/// above this package deals in `@Model` objects.
@Model
public final class StoredCameraBody {
    public var identifier: UUID = UUID()
    public var name: String = ""
    /// Seconds. `1/250`, never `250`.
    public var shutterSpeeds: [TimeInterval] = []
    /// A loaded roll's speed, when film is loaded.
    public var fixedISO: Int?
    public var minimumISO: Int?
    public var maximumISO: Int?
    public var circleOfConfusionMillimetres: Double = 0.030
    public var hasMeter: Bool = true
    public var loadedFilm: String?

    public init(_ body: CameraBody) {
        identifier = body.id
        name = body.name
        shutterSpeeds = body.sortedShutterSpeeds
        circleOfConfusionMillimetres = body.circleOfConfusionMillimetres
        hasMeter = body.hasMeter
        loadedFilm = body.loadedFilm
        apply(body.iso)
    }

    public func apply(_ iso: ISOMode) {
        switch iso {
        case let .fixed(value):
            fixedISO = value
            minimumISO = nil
            maximumISO = nil
        case let .range(minimum, maximum):
            fixedISO = nil
            minimumISO = minimum
            maximumISO = maximum
        }
    }

    /// The value type. Falls back to ISO 100 only if the row is corrupt, which
    /// the seeder cannot produce.
    public var value: CameraBody {
        let iso: ISOMode
        if let fixedISO {
            iso = .fixed(fixedISO)
        } else {
            iso = .range(minimum: minimumISO ?? 100, maximum: maximumISO ?? 100)
        }
        return CameraBody(
            id: identifier,
            name: name,
            shutterSpeeds: shutterSpeeds,
            iso: iso,
            circleOfConfusionMillimetres: circleOfConfusionMillimetres,
            hasMeter: hasMeter,
            loadedFilm: loadedFilm
        )
    }
}

/// A stored lens.
///
/// The engraved marks are the reason this table exists; `∞` is engraved on all
/// of these lenses and is stored as a flag beside the finite marks, because a
/// non-finite `Double` in a database column is a trap for whoever reads it next.
@Model
public final class StoredLens {
    public var identifier: UUID = UUID()
    public var name: String = ""
    public var focalLengthMillimetres: Double = 50
    /// The real click stops, as f-numbers.
    public var apertures: [Double] = []
    /// The finite marks engraved on the barrel, metres, ascending.
    public var finiteDistanceMarksMetres: [Double] = []
    public var hasInfinityMark: Bool = true
    public var minimumFocusMetres: Double = 0.7

    public init(_ lens: Lens) {
        identifier = lens.id
        name = lens.name
        focalLengthMillimetres = lens.focalLengthMillimetres
        apertures = lens.sortedApertures
        finiteDistanceMarksMetres = lens.sortedDistanceMarks.filter(\.isFinite)
        hasInfinityMark = lens.distanceMarksMetres.contains { !$0.isFinite }
        minimumFocusMetres = lens.minimumFocusMetres
    }

    public var value: Lens {
        Lens(
            id: identifier,
            name: name,
            focalLengthMillimetres: focalLengthMillimetres,
            apertures: apertures,
            distanceMarksMetres: finiteDistanceMarksMetres + (hasInfinityMark ? [.infinity] : []),
            minimumFocusMetres: minimumFocusMetres
        )
    }
}

/// A body, a lens and how this photographer works.
@Model
public final class StoredGearProfile {
    public var identifier: UUID = UUID()
    public var name: String = ""
    public var body: StoredCameraBody?
    public var lens: StoredLens?
    /// `TDMCore.ExposureStrategy.rawValue`.
    public var strategyRawValue: String = ExposureStrategy.zoneFocus.rawValue
    /// A body-wide meter correction, distinct from the per-scene calibration.
    public var calibrationOffsetEV: Double = 0
    /// Exactly one profile is selected; ``GearStore`` maintains that.
    public var isSelected: Bool = false

    public init(_ profile: GearProfile, body: StoredCameraBody, lens: StoredLens, isSelected: Bool = false) {
        identifier = profile.id
        name = profile.name
        self.body = body
        self.lens = lens
        strategyRawValue = profile.strategy.rawValue
        calibrationOffsetEV = profile.calibrationOffsetEV
        self.isSelected = isSelected
    }

    /// `nil` when the row has lost its body or lens, which SwiftData allows a
    /// deletion to do. The store filters those out rather than inventing gear.
    public var value: GearProfile? {
        guard let body, let lens else { return nil }
        return GearProfile(
            id: identifier,
            name: name,
            body: body.value,
            lens: lens.value,
            strategy: ExposureStrategy(rawValue: strategyRawValue) ?? .zoneFocus,
            calibrationOffsetEV: calibrationOffsetEV
        )
    }
}

/// A stored per-scene calibration offset, one row per (scene, light source).
@Model
public final class StoredCalibrationOffset {
    public var sceneIdentifier: String = ""
    public var isArtificialLight: Bool = false
    public var offsetEV: Double = 0
    public var measuredAt: Date = Date()

    public init(_ offset: CalibrationOffset) {
        sceneIdentifier = offset.sceneIdentifier
        isArtificialLight = offset.isArtificialLight
        offsetEV = offset.offsetEV
        measuredAt = offset.measuredAt
    }

    public var value: CalibrationOffset {
        CalibrationOffset(
            sceneIdentifier: sceneIdentifier,
            isArtificialLight: isArtificialLight,
            offsetEV: offsetEV,
            measuredAt: measuredAt
        )
    }
}
#endif
