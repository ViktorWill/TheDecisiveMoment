import Foundation
import Testing
@testable import TDMCore

/// The contract every ``CommunityBackend`` has to keep, exercised against the
/// in-memory one. `TDMPersistence` runs the same expectations against SwiftData.
@Suite("CommunityBackend")
struct CommunityBackendTests {
    private let host = Photographer(displayName: "Host")

    private func session(
        title: String = "Kreuzberg morning",
        startsAt: Date,
        cityId: String = "de-berlin",
        maxPeople: Int? = nil,
        hostId: UUID
    ) -> ShootSession {
        ShootSession(
            cityId: cityId,
            title: title,
            startsAt: startsAt,
            duration: 3600 * 2,
            meetingPoint: Coordinate(latitude: 52.4996, longitude: 13.4180),
            maxPeople: maxPeople,
            hostId: hostId
        )
    }

    @Test("A created session comes back, soonest first")
    func createAndList() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backend = InMemoryCommunityBackend(profile: host)
        let later = session(title: "Later", startsAt: now.addingTimeInterval(7200), hostId: host.id)
        let sooner = session(title: "Sooner", startsAt: now.addingTimeInterval(3600), hostId: host.id)
        _ = try await backend.create(later)
        _ = try await backend.create(sooner)

        let listed = try await backend.sessions(from: now)
        #expect(listed.map(\.title) == ["Sooner", "Later"])
    }

    @Test("Finished sessions drop out of the list")
    func pastSessionsAreExcluded() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backend = InMemoryCommunityBackend(profile: host)
        // Started three hours ago and ran for two: over.
        _ = try await backend.create(session(startsAt: now.addingTimeInterval(-3 * 3600), hostId: host.id))

        #expect(try await backend.sessions(from: now).isEmpty)
    }

    @Test("City scoping filters, and nothing else does")
    func cityScope() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backend = InMemoryCommunityBackend(profile: host)
        _ = try await backend.create(session(startsAt: now.addingTimeInterval(60), hostId: host.id))
        _ = try await backend.create(
            session(startsAt: now.addingTimeInterval(60), cityId: "us-nyc", hostId: host.id)
        )

        #expect(try await backend.sessions(in: "us-nyc", from: now).count == 1)
        #expect(try await backend.sessions(from: now).count == 2)
    }

    @Test("An invalid session is refused rather than stored")
    func invalidSessionIsRefused() async throws {
        let backend = InMemoryCommunityBackend(profile: host)
        var blank = session(startsAt: .now, hostId: host.id)
        blank.title = "   "

        await #expect(throws: CommunityError.invalidSession) {
            _ = try await backend.create(blank)
        }
    }

    @Test("Editing an unknown session is an error, not a silent insert")
    func updateUnknown() async throws {
        let backend = InMemoryCommunityBackend(profile: host)
        let unknown = session(startsAt: .now, hostId: host.id)

        await #expect(throws: CommunityError.sessionNotFound(id: unknown.id)) {
            _ = try await backend.update(unknown)
        }
    }

    @Test("Edit then cancel")
    func updateAndCancel() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backend = InMemoryCommunityBackend(profile: host)
        var stored = try await backend.create(session(startsAt: now.addingTimeInterval(60), hostId: host.id))
        stored.title = "Renamed"
        stored.notes = "Meet by the fountain"
        _ = try await backend.update(stored)

        #expect(try await backend.sessions(from: now).first?.title == "Renamed")

        try await backend.cancel(id: stored.id)
        #expect(try await backend.sessions(from: now).isEmpty)
        await #expect(throws: CommunityError.sessionNotFound(id: stored.id)) {
            try await backend.cancel(id: stored.id)
        }
    }

    @Test("The host cannot join their own session twice")
    func hostCannotJoin() async throws {
        let backend = InMemoryCommunityBackend(profile: host)
        let stored = try await backend.create(session(startsAt: .now.addingTimeInterval(60), hostId: host.id))

        await #expect(throws: CommunityError.alreadyAttending(id: stored.id)) {
            try await backend.join(sessionId: stored.id)
        }
    }

    @Test("Joining a full session fails; the host counts against the cap")
    func joinFull() async throws {
        let stranger = Photographer(displayName: "Someone else")
        let backend = InMemoryCommunityBackend(profile: stranger)
        let full = try await backend.create(
            session(startsAt: .now.addingTimeInterval(60), maxPeople: 1, hostId: host.id)
        )

        await #expect(throws: CommunityError.sessionFull(id: full.id)) {
            try await backend.join(sessionId: full.id)
        }
    }

    @Test("Join then leave puts the attendee list back")
    func joinThenLeave() async throws {
        let stranger = Photographer(displayName: "Someone else")
        let backend = InMemoryCommunityBackend(profile: stranger)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = try await backend.create(
            session(startsAt: now.addingTimeInterval(60), maxPeople: 4, hostId: host.id)
        )

        try await backend.join(sessionId: stored.id)
        #expect(try await backend.sessions(from: now).first?.attendeeIds == [stranger.id])

        try await backend.leave(sessionId: stored.id)
        #expect(try await backend.sessions(from: now).first?.attendeeIds.isEmpty == true)
    }

    @Test("A profile round-trips, and a blank name is refused")
    func profileRoundTrip() async throws {
        let backend = InMemoryCommunityBackend()
        var profile = try await backend.profile()
        #expect(profile.displayName == Photographer.defaultDisplayName)

        profile.displayName = "Viktor"
        profile.gearSummary = "M6 · 35mm"
        _ = try await backend.save(profile)
        #expect(try await backend.profile().gearSummary == "M6 · 35mm")

        profile.displayName = " "
        await #expect(throws: CommunityError.invalidProfile) {
            _ = try await backend.save(profile)
        }
    }

    @Test("Sessions default to private")
    func defaultVisibility() {
        let plan = session(startsAt: .now, hostId: host.id)
        #expect(plan.visibility == .private)
    }
}
