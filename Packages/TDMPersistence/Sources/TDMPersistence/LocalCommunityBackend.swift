#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore

/// The v1 ``TDMCore/CommunityBackend``: SwiftData on the device, and nothing
/// leaves it.
///
/// A model actor, like ``SwiftDataSpotStore``, so the list query does not run
/// on the main actor and so the `@Model` classes never cross the boundary —
/// only `TDMCore` value types do.
@ModelActor
public actor LocalCommunityBackend: CommunityBackend {
    /// The models this backend owns. The app passes these to its container.
    public static var models: [any PersistentModel.Type] {
        [StoredShootSession.self, StoredPhotographer.self]
    }

    public static func make(container: ModelContainer) -> LocalCommunityBackend {
        LocalCommunityBackend(modelContainer: container)
    }

    /// A container for the community models. `inMemory` is for previews and
    /// tests.
    ///
    /// `"community"`: this app also has a spot store and a gear store, each
    /// with their own container — see `ModelStoreLocation`.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: try ModelStoreLocation.url(named: "community"))
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }

    // MARK: - Reading

    public func sessions(in cityId: String, from: Date) throws -> [ShootSession] {
        try upcoming(from: from).filter { $0.cityId == cityId }
    }

    public func sessions(from: Date) throws -> [ShootSession] {
        try upcoming(from: from)
    }

    /// Sorted in the store and filtered in memory: "has not finished yet" is
    /// `startsAt + duration > from`, which is arithmetic a `#Predicate` cannot
    /// express, and a personal plan is tens of rows rather than thousands.
    private func upcoming(from: Date) throws -> [ShootSession] {
        try modelContext
            .fetch(FetchDescriptor<StoredShootSession>(sortBy: [SortDescriptor(\.startsAt)]))
            .map(\.value)
            .filter { $0.isUpcoming(at: from) }
    }

    // MARK: - Writing

    public func create(_ session: ShootSession) throws -> ShootSession {
        guard session.isValid else { throw CommunityError.invalidSession }
        modelContext.insert(StoredShootSession(session))
        try save()
        return session
    }

    public func update(_ session: ShootSession) throws -> ShootSession {
        guard let row = try row(id: session.id) else {
            throw CommunityError.sessionNotFound(id: session.id)
        }
        guard session.isValid else { throw CommunityError.invalidSession }
        row.apply(session)
        try save()
        return session
    }

    public func cancel(id: ShootSession.ID) throws {
        guard let row = try row(id: id) else { throw CommunityError.sessionNotFound(id: id) }
        modelContext.delete(row)
        try save()
    }

    public func join(sessionId: ShootSession.ID) throws {
        guard let row = try row(id: sessionId) else {
            throw CommunityError.sessionNotFound(id: sessionId)
        }
        let me = try localProfileRow().id
        var session = row.value
        guard session.hostId != me, !session.attendeeIds.contains(me) else {
            throw CommunityError.alreadyAttending(id: sessionId)
        }
        guard !session.isFull else { throw CommunityError.sessionFull(id: sessionId) }
        session.attendeeIds.append(me)
        row.apply(session)
        try save()
    }

    public func leave(sessionId: ShootSession.ID) throws {
        guard let row = try row(id: sessionId) else {
            throw CommunityError.sessionNotFound(id: sessionId)
        }
        let me = try localProfileRow().id
        var session = row.value
        session.attendeeIds.removeAll { $0 == me }
        row.apply(session)
        try save()
    }

    // MARK: - Profile

    public func profile() throws -> Photographer {
        try localProfileRow().value
    }

    public func save(_ profile: Photographer) throws -> Photographer {
        guard profile.isValid else { throw CommunityError.invalidProfile }
        let row = try localProfileRow()
        // The id is the host id of every session already stored, so an edit
        // updates the existing row rather than inserting a second person.
        row.apply(profile)
        try save()
        return row.value
    }

    /// The one photographer row, seeded on first use so a session always has a
    /// host id to point at.
    private func localProfileRow() throws -> StoredPhotographer {
        if let existing = try modelContext.fetch(FetchDescriptor<StoredPhotographer>()).first {
            return existing
        }
        let seeded = StoredPhotographer(Photographer(displayName: Photographer.defaultDisplayName))
        modelContext.insert(seeded)
        try save()
        return seeded
    }

    // MARK: - Support

    private func row(id: UUID) throws -> StoredShootSession? {
        try modelContext
            .fetch(FetchDescriptor<StoredShootSession>(predicate: #Predicate { $0.id == id }))
            .first
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw CommunityError.storageFailed(description: String(describing: error))
        }
    }
}
#endif
