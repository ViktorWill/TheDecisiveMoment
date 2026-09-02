import Foundation
import Testing
@testable import TDMCore

@Suite("Gear profiles — SPEC-light.md")
struct GearTests {
    static let m6 = CameraBody(
        name: "M6",
        shutterSpeeds: [1, 1.0 / 2, 1.0 / 4, 1.0 / 8, 1.0 / 15, 1.0 / 30, 1.0 / 60, 1.0 / 125, 1.0 / 250, 1.0 / 500, 1.0 / 1000],
        iso: .fixed(400),
        loadedFilm: "Tri-X 400"
    )

    static let summicron35 = Lens(
        name: "Summicron 35mm f/2",
        focalLengthMillimetres: 35,
        apertures: [2, 2.8, 4, 5.6, 8, 11, 16],
        distanceMarksMetres: [0.7, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, 5.0, 10.0, .infinity],
        minimumFocusMetres: 0.7
    )

    @Test("A film body offers exactly one ISO, because the roll is loaded")
    func filmISO() {
        #expect(Self.m6.iso.isFilm)
        #expect(Self.m6.iso.availableValues == [400])
    }

    @Test("A digital body enumerates full stops from its minimum")
    func digitalISO() {
        let iso = ISOMode.range(minimum: 100, maximum: 6400)

        #expect(!iso.isFilm)
        #expect(iso.availableValues == [100, 200, 400, 800, 1600, 3200, 6400])
        #expect(ISOMode.range(minimum: 400, maximum: 100).availableValues.isEmpty)
    }

    /// The persisted shape has to be legible in a diff and writable by hand in
    /// a seed profile, which the synthesised enum encoding is not.
    @Test("ISO mode round-trips through a readable JSON shape")
    func isoModeCoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let fixed = String(decoding: try encoder.encode(ISOMode.fixed(400)), as: UTF8.self)
        #expect(fixed == #"{"mode":"fixed","value":400}"#)

        let range = String(decoding: try encoder.encode(ISOMode.range(minimum: 100, maximum: 6400)), as: UTF8.self)
        #expect(range == #"{"maximum":6400,"minimum":100,"mode":"range"}"#)

        let decoded = try JSONDecoder().decode(ISOMode.self, from: Data(range.utf8))
        #expect(decoded == .range(minimum: 100, maximum: 6400))
    }

    @Test("Validation catches gear that would produce unusable advice")
    func validation() {
        var body = Self.m6
        #expect(body.isValid)
        // A shutter ladder in integers rather than seconds is the classic bug;
        // it survives validation, so the type comment is the defence — but an
        // empty or negative ladder does not.
        body.shutterSpeeds = []
        #expect(!body.isValid)

        var lens = Self.summicron35
        #expect(lens.isValid)
        lens.distanceMarksMetres = []
        #expect(!lens.isValid)
    }

    @Test("A profile summarises as a conversation starter")
    func profileSummary() {
        let profile = GearProfile(name: "Everyday", body: Self.m6, lens: Self.summicron35)

        #expect(profile.summary == "M6 · 35mm")
        #expect(profile.strategy == .zoneFocus)
        #expect(profile.isValid)
    }

    /// JSON has no infinity, and the ∞ mark is on every one of these barrels,
    /// so it has to survive a round trip through storage as something else.
    @Test("A whole profile round-trips, infinity mark included")
    func profileRoundTrips() throws {
        let profile = GearProfile(
            name: "Everyday",
            body: Self.m6,
            lens: Self.summicron35,
            strategy: .freezeMotion,
            calibrationOffsetEV: -0.3
        )

        let data = try JSONEncoder().encode(profile)
        let restored = try JSONDecoder().decode(GearProfile.self, from: data)

        #expect(restored == profile)
        #expect(restored.lens.sortedDistanceMarks.last == .infinity)
        #expect(!String(decoding: data, as: UTF8.self).contains("inf"))
    }
}

@Suite("Community model — SPEC-community.md")
struct CommunityTests {
    static func session(visibility: Visibility = .private, maxPeople: Int? = nil, attendees: [UUID] = []) -> ShootSession {
        ShootSession(
            cityId: "us-nyc",
            spotId: "curated:us-nyc/fifth-42nd",
            title: "Saturday morning, Midtown",
            startsAt: Date(timeIntervalSince1970: 1_756_699_920),
            duration: 2 * 3600,
            meetingPoint: Coordinate(latitude: 40.7535, longitude: -73.9813),
            notes: "Meet by the northeast corner.",
            maxPeople: maxPeople,
            hostId: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            attendeeIds: attendees,
            visibility: visibility
        )
    }

    /// Broadcasting where a person will be at a specific time is sensitive, so
    /// the default has to be the private one.
    @Test("A session defaults to private")
    func defaultsToPrivate() {
        let session = ShootSession(
            cityId: "us-nyc",
            title: "Walk",
            startsAt: Date(timeIntervalSince1970: 0),
            duration: 3600,
            meetingPoint: Coordinate(latitude: 40.75, longitude: -73.98),
            hostId: UUID()
        )

        #expect(session.visibility == .private)
        #expect(session.attendeeIds.isEmpty)
    }

    @Test("The host counts against the cap")
    func hostCountsAgainstTheCap() {
        #expect(!Self.session(maxPeople: 4, attendees: [UUID(), UUID()]).isFull)
        #expect(Self.session(maxPeople: 3, attendees: [UUID(), UUID()]).isFull)
        #expect(!Self.session(maxPeople: nil, attendees: [UUID()]).isFull)
    }

    @Test("A session knows when it ends and whether it is still ahead")
    func timing() {
        let session = Self.session()

        #expect(session.endsAt == session.startsAt.addingTimeInterval(7200))
        #expect(session.isUpcoming(at: session.startsAt.addingTimeInterval(3600)))
        #expect(!session.isUpcoming(at: session.endsAt.addingTimeInterval(1)))
    }

    @Test("Validation catches sessions that cannot be honoured")
    func validation() {
        #expect(Self.session().isValid)

        var empty = Self.session()
        empty.title = "  "
        #expect(!empty.isValid)

        var backwards = Self.session()
        backwards.duration = 0
        #expect(!backwards.isValid)

        var doubleBooked = Self.session()
        doubleBooked.attendeeIds = [doubleBooked.hostId]
        #expect(!doubleBooked.isValid)
    }

    @Test("A session round-trips")
    func roundTrips() throws {
        let session = Self.session(visibility: .city, maxPeople: 5)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(ShootSession.self, from: encoder.encode(session)) == session)
    }

    @Test("A photographer needs a name to be shown at all")
    func photographerValidation() {
        #expect(Photographer(displayName: "V.", gearSummary: "M6 · 35mm", cities: ["us-nyc"]).isValid)
        #expect(!Photographer(displayName: " ").isValid)
    }
}
