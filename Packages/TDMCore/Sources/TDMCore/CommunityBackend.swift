import Foundation

/// Sessions and the person who plans them, wherever they happen to be stored.
///
/// v1 has exactly one implementation, `TDMPersistence.LocalCommunityBackend`,
/// and the sessions never leave the device. The protocol exists now so that the
/// views bind to it rather than to SwiftData, and phase 3's server implementation
/// is a swap at the composition root — `docs/SPEC-community.md`.
public protocol CommunityBackend: Sendable {
    /// Sessions in one city that have not finished by `from`, soonest first.
    func sessions(in cityId: String, from: Date) async throws -> [ShootSession]

    /// Every session that has not finished by `from`, soonest first.
    ///
    /// Not in the phase 3 shape, which is always city-scoped: a server browses
    /// one city at a time, but a personal plan spans however many cities the
    /// photographer travels to, and asking them to pick a city before they can
    /// see their own list would be an invented step.
    func sessions(from: Date) async throws -> [ShootSession]

    func create(_ session: ShootSession) async throws -> ShootSession
    func update(_ session: ShootSession) async throws -> ShootSession
    func cancel(id: ShootSession.ID) async throws
    func join(sessionId: ShootSession.ID) async throws
    func leave(sessionId: ShootSession.ID) async throws

    /// The local photographer, created on first call so that a session always
    /// has a host id.
    func profile() async throws -> Photographer

    /// Stores an edited profile.
    ///
    /// Phase 3 gets this from the account, so the spec's original list did not
    /// have it. In v1 there is no account, and the display name has to be
    /// editable somewhere.
    func save(_ profile: Photographer) async throws -> Photographer
}

/// What can go wrong, in terms the UI can act on.
public enum CommunityError: Error, Equatable, Sendable {
    /// No session with that id — most likely deleted on another screen.
    case sessionNotFound(id: UUID)
    /// The session failed ``ShootSession/isValid``: an empty title, a duration
    /// of zero, a meeting point off the globe.
    case invalidSession
    case invalidProfile
    /// The cap has been reached. Kept in v1 even though only the host attends,
    /// because the rule belongs with the model rather than with the server.
    case sessionFull(id: UUID)
    /// The host is already attending by definition and cannot join twice.
    case alreadyAttending(id: UUID)
    case storageFailed(description: String)
}

/// A backend that keeps everything in memory: previews, tests, and any device
/// whose store will not open.
///
/// Losing a plan when the app quits is bad; refusing to draw the tab because
/// SwiftData failed is worse.
public actor InMemoryCommunityBackend: CommunityBackend {
    private var storedSessions: [UUID: ShootSession] = [:]
    private var storedProfile: Photographer

    public init(
        profile: Photographer = Photographer(displayName: Photographer.defaultDisplayName),
        sessions: [ShootSession] = []
    ) {
        storedProfile = profile
        for session in sessions { storedSessions[session.id] = session }
    }

    public func sessions(in cityId: String, from: Date) async throws -> [ShootSession] {
        try await sessions(from: from).filter { $0.cityId == cityId }
    }

    public func sessions(from: Date) async throws -> [ShootSession] {
        storedSessions.values
            .filter { $0.isUpcoming(at: from) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    public func create(_ session: ShootSession) async throws -> ShootSession {
        guard session.isValid else { throw CommunityError.invalidSession }
        storedSessions[session.id] = session
        return session
    }

    public func update(_ session: ShootSession) async throws -> ShootSession {
        guard storedSessions[session.id] != nil else {
            throw CommunityError.sessionNotFound(id: session.id)
        }
        guard session.isValid else { throw CommunityError.invalidSession }
        storedSessions[session.id] = session
        return session
    }

    public func cancel(id: ShootSession.ID) async throws {
        guard storedSessions.removeValue(forKey: id) != nil else {
            throw CommunityError.sessionNotFound(id: id)
        }
    }

    public func join(sessionId: ShootSession.ID) async throws {
        guard var session = storedSessions[sessionId] else {
            throw CommunityError.sessionNotFound(id: sessionId)
        }
        let me = storedProfile.id
        guard session.hostId != me, !session.attendeeIds.contains(me) else {
            throw CommunityError.alreadyAttending(id: sessionId)
        }
        guard !session.isFull else { throw CommunityError.sessionFull(id: sessionId) }
        session.attendeeIds.append(me)
        storedSessions[sessionId] = session
    }

    public func leave(sessionId: ShootSession.ID) async throws {
        guard var session = storedSessions[sessionId] else {
            throw CommunityError.sessionNotFound(id: sessionId)
        }
        session.attendeeIds.removeAll { $0 == storedProfile.id }
        storedSessions[sessionId] = session
    }

    public func profile() async throws -> Photographer { storedProfile }

    public func save(_ profile: Photographer) async throws -> Photographer {
        guard profile.isValid else { throw CommunityError.invalidProfile }
        storedProfile = profile
        return profile
    }
}
