#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore

/// The gear side of the local store: profiles, bodies, lenses and calibration
/// offsets, seeded on first launch from ``GearCatalogue``.
///
/// Everything crossing this boundary is a `TDMCore` value type; the `@Model`
/// classes never leave.
@MainActor
public final class GearStore {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// The models this store owns. The app passes these to its container.
    public static var models: [any PersistentModel.Type] {
        [StoredGearProfile.self, StoredCameraBody.self, StoredLens.self, StoredCalibrationOffset.self]
    }

    /// A container for the gear models. `inMemory` is for previews and tests.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }

    // MARK: - Seeding

    /// Seeds the shipped bodies, lenses and profiles the first time the app
    /// runs. Does nothing when a profile already exists, so a user who has
    /// deleted the seeds does not get them back on every launch.
    @discardableResult
    public func seedIfEmpty() throws -> Bool {
        let existing = try context.fetchCount(FetchDescriptor<StoredGearProfile>())
        guard existing == 0 else { return false }

        var bodies: [String: StoredCameraBody] = [:]
        for body in GearCatalogue.bodies {
            let stored = StoredCameraBody(body)
            context.insert(stored)
            bodies[body.name] = stored
        }
        var lenses: [String: StoredLens] = [:]
        for lens in GearCatalogue.lenses {
            let stored = StoredLens(lens)
            context.insert(stored)
            lenses[lens.name] = stored
        }
        for (index, profile) in GearCatalogue.profiles.enumerated() {
            guard let body = bodies[profile.body.name], let lens = lenses[profile.lens.name] else { continue }
            context.insert(StoredGearProfile(profile, body: body, lens: lens, isSelected: index == 0))
        }
        try context.save()
        return true
    }

    // MARK: - Reading

    public func profiles() throws -> [GearProfile] {
        try context
            .fetch(FetchDescriptor<StoredGearProfile>(sortBy: [SortDescriptor(\.name)]))
            .compactMap(\.value)
    }

    public func bodies() throws -> [CameraBody] {
        try context
            .fetch(FetchDescriptor<StoredCameraBody>(sortBy: [SortDescriptor(\.name)]))
            .map(\.value)
    }

    public func lenses() throws -> [Lens] {
        try context
            .fetch(FetchDescriptor<StoredLens>(sortBy: [SortDescriptor(\.focalLengthMillimetres)]))
            .map(\.value)
    }

    /// The profile the Light screen is using, or the first one there is.
    public func selectedProfile() throws -> GearProfile? {
        let stored = try context.fetch(FetchDescriptor<StoredGearProfile>(sortBy: [SortDescriptor(\.name)]))
        return (stored.first(where: \.isSelected) ?? stored.first)?.value
    }

    public func select(_ profile: GearProfile) throws {
        let stored = try context.fetch(FetchDescriptor<StoredGearProfile>())
        for row in stored {
            row.isSelected = row.identifier == profile.id
        }
        try context.save()
    }

    // MARK: - Writing

    /// Inserts or updates a profile, along with the body and lens it names.
    public func save(_ profile: GearProfile) throws {
        let body = try storedBody(profile.body)
        let lens = try storedLens(profile.lens)

        let identifier = profile.id
        let descriptor = FetchDescriptor<StoredGearProfile>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.name = profile.name
            existing.body = body
            existing.lens = lens
            existing.strategyRawValue = profile.strategy.rawValue
            existing.calibrationOffsetEV = profile.calibrationOffsetEV
        } else {
            let isFirst = try context.fetchCount(FetchDescriptor<StoredGearProfile>()) == 0
            context.insert(StoredGearProfile(profile, body: body, lens: lens, isSelected: isFirst))
        }
        try context.save()
    }

    public func delete(_ profile: GearProfile) throws {
        let identifier = profile.id
        let descriptor = FetchDescriptor<StoredGearProfile>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        for row in try context.fetch(descriptor) {
            context.delete(row)
        }
        try context.save()
    }

    // MARK: - Calibration

    /// Every stored offset, newest first.
    public func calibrationOffsets() throws -> [CalibrationOffset] {
        try context
            .fetch(FetchDescriptor<StoredCalibrationOffset>(sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]))
            .map(\.value)
    }

    /// The offset for a scene, if the user has measured one.
    public func calibrationOffset(
        sceneIdentifier: String,
        isArtificialLight: Bool
    ) throws -> CalibrationOffset? {
        let descriptor = FetchDescriptor<StoredCalibrationOffset>(
            predicate: #Predicate {
                $0.sceneIdentifier == sceneIdentifier && $0.isArtificialLight == isArtificialLight
            }
        )
        return try context.fetch(descriptor).first?.value
    }

    /// Stores a measured offset, replacing any earlier one for the same scene.
    ///
    /// Implausible offsets are rejected rather than stored: a reading taken with
    /// the lens cap on would otherwise poison every future estimate.
    @discardableResult
    public func storeCalibration(_ offset: CalibrationOffset) throws -> Bool {
        guard offset.isPlausible else { return false }
        let scene = offset.sceneIdentifier
        let artificial = offset.isArtificialLight
        let descriptor = FetchDescriptor<StoredCalibrationOffset>(
            predicate: #Predicate {
                $0.sceneIdentifier == scene && $0.isArtificialLight == artificial
            }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.offsetEV = offset.offsetEV
            existing.measuredAt = offset.measuredAt
        } else {
            context.insert(StoredCalibrationOffset(offset))
        }
        try context.save()
        return true
    }

    public func clearCalibration(sceneIdentifier: String, isArtificialLight: Bool) throws {
        let descriptor = FetchDescriptor<StoredCalibrationOffset>(
            predicate: #Predicate {
                $0.sceneIdentifier == sceneIdentifier && $0.isArtificialLight == isArtificialLight
            }
        )
        for row in try context.fetch(descriptor) {
            context.delete(row)
        }
        try context.save()
    }

    // MARK: - Support

    private func storedBody(_ body: CameraBody) throws -> StoredCameraBody {
        let identifier = body.id
        let descriptor = FetchDescriptor<StoredCameraBody>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.name = body.name
            existing.shutterSpeeds = body.sortedShutterSpeeds
            existing.circleOfConfusionMillimetres = body.circleOfConfusionMillimetres
            existing.hasMeter = body.hasMeter
            existing.loadedFilm = body.loadedFilm
            existing.apply(body.iso)
            return existing
        }
        let stored = StoredCameraBody(body)
        context.insert(stored)
        return stored
    }

    private func storedLens(_ lens: Lens) throws -> StoredLens {
        let identifier = lens.id
        let descriptor = FetchDescriptor<StoredLens>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.name = lens.name
            existing.focalLengthMillimetres = lens.focalLengthMillimetres
            existing.apertures = lens.sortedApertures
            existing.finiteDistanceMarksMetres = lens.sortedDistanceMarks.filter(\.isFinite)
            existing.hasInfinityMark = lens.distanceMarksMetres.contains { !$0.isFinite }
            existing.minimumFocusMetres = lens.minimumFocusMetres
            return existing
        }
        let stored = StoredLens(lens)
        context.insert(stored)
        return stored
    }
}
#endif
