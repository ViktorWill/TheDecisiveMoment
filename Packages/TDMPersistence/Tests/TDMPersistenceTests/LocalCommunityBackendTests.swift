#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import TDMCore
@testable import TDMPersistence

/// The same contract ``TDMCore/InMemoryCommunityBackend`` is held to, against
/// the store that actually ships. Only builds where SwiftData does, so this is
/// exercised by the macOS job rather than on Linux.
@Suite("LocalCommunityBackend — SPEC-community.md")
struct LocalCommunityBackendTests {
    private func makeBackend() throws -> LocalCommunityBackend {
        LocalCommunityBackend.make(container: try LocalCommunityBackend.makeContainer(inMemory: true))
    }

    private func session(
        title: String = "Kreuzberg morning",
        startsAt: Date,
        cityId: String = "de-berlin",
        spotId: String? = nil,
        hostId: UUID
    ) -> ShootSession {
        ShootSession(
            cityId: cityId,
            spotId: spotId,
            title: title,
            startsAt: startsAt,
            duration: 2 * 3600,
            meetingPoint: Coordinate(latitude: 52.4996, longitude: 13.4180),
            notes: "Bring the 35",
            hostId: hostId
        )
    }

    @Test("A session round-trips through the store, spot anchor included")
    func roundTrip() async throws {
        let backend = try makeBackend()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let host = try await backend.profile()
        let plan = session(startsAt: now.addingTimeInterval(3600), spotId: "local:abc", hostId: host.id)

        _ = try await backend.create(plan)
        let stored = try await backend.sessions(from: now)
        #expect(stored == [plan])
        #expect(stored.first?.visibility == .private)
    }

    @Test("Sessions come back soonest first, and finished ones do not come back")
    func ordering() async throws {
        let backend = try makeBackend()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let host = try await backend.profile()
        _ = try await backend.create(session(title: "Later", startsAt: now.addingTimeInterval(7200), hostId: host.id))
        _ = try await backend.create(session(title: "Sooner", startsAt: now.addingTimeInterval(60), hostId: host.id))
        _ = try await backend.create(session(title: "Over", startsAt: now.addingTimeInterval(-3 * 3600), hostId: host.id))

        #expect(try await backend.sessions(from: now).map(\.title) == ["Sooner", "Later"])
    }

    @Test("City scoping")
    func cityScope() async throws {
        let backend = try makeBackend()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let host = try await backend.profile()
        _ = try await backend.create(session(startsAt: now.addingTimeInterval(60), hostId: host.id))
        _ = try await backend.create(
            session(startsAt: now.addingTimeInterval(60), cityId: "us-nyc", hostId: host.id)
        )

        #expect(try await backend.sessions(in: "us-nyc", from: now).count == 1)
    }

    @Test("Editing rewrites the row; cancelling removes it")
    func updateAndCancel() async throws {
        let backend = try makeBackend()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let host = try await backend.profile()
        var plan = try await backend.create(session(startsAt: now.addingTimeInterval(60), hostId: host.id))

        plan.title = "Renamed"
        plan.spotId = nil
        _ = try await backend.update(plan)
        #expect(try await backend.sessions(from: now) == [plan])

        try await backend.cancel(id: plan.id)
        #expect(try await backend.sessions(from: now).isEmpty)
        await #expect(throws: CommunityError.sessionNotFound(id: plan.id)) {
            try await backend.cancel(id: plan.id)
        }
    }

    @Test("An invalid session is refused rather than stored")
    func invalidIsRefused() async throws {
        let backend = try makeBackend()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let host = try await backend.profile()
        var blank = session(startsAt: now.addingTimeInterval(60), hostId: host.id)
        blank.title = "  "

        await #expect(throws: CommunityError.invalidSession) {
            _ = try await backend.create(blank)
        }
        #expect(try await backend.sessions(from: now).isEmpty)
    }

    @Test("The profile is seeded once and edited in place")
    func profileIsASingleRow() async throws {
        let backend = try makeBackend()
        var profile = try await backend.profile()
        #expect(profile.displayName == Photographer.defaultDisplayName)

        profile.displayName = "Viktor"
        profile.gearSummary = "M6 · 35mm"
        _ = try await backend.save(profile)

        let reread = try await backend.profile()
        #expect(reread.id == profile.id)
        #expect(reread.gearSummary == "M6 · 35mm")
    }

    @Test("The host is already attending, so joining their own plan fails")
    func hostCannotJoin() async throws {
        let backend = try makeBackend()
        let host = try await backend.profile()
        let plan = try await backend.create(session(startsAt: .now.addingTimeInterval(60), hostId: host.id))

        await #expect(throws: CommunityError.alreadyAttending(id: plan.id)) {
            try await backend.join(sessionId: plan.id)
        }
    }
}
#endif
