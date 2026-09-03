import Foundation

/// Who can see a session.
///
/// Broadcasting where a person will be at a specific time is sensitive, so the
/// default is `private` and anything wider is an explicit choice —
/// `docs/SPEC-community.md`.
public enum Visibility: String, Sendable, Codable, CaseIterable, Hashable {
    /// Only the host. Every v1 session is effectively this.
    case `private`
    /// Anyone holding the link.
    case link
    /// Everyone browsing that city.
    case city
}

/// Someone who shoots. Local-only in v1.
public struct Photographer: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var displayName: String
    /// "M6 · 35mm" — a conversation starter, not a spec sheet.
    public var gearSummary: String?
    public var bio: String?
    /// City ids, matching `CityIndexEntry.cityId`.
    public var cities: [String]

    public init(
        id: UUID = UUID(),
        displayName: String,
        gearSummary: String? = nil,
        bio: String? = nil,
        cities: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.cities = cities
        self.gearSummary = gearSummary
        self.bio = bio
    }

    public var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What a profile is called before anyone has been asked. v1 has no
    /// account, so the local photographer is seeded rather than signed in.
    public static let defaultDisplayName = "You"
}

/// A plan to go out and shoot.
///
/// v1 stores these locally and shows them to nobody else; the shape is fixed
/// now so the model does not have to be rewritten when a backend arrives.
public struct ShootSession: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var cityId: String
    /// Optional anchor into the map.
    public var spotId: String?
    public var title: String
    public var startsAt: Date
    public var duration: TimeInterval
    /// Public places only. This is a physical-safety rule, not a convention.
    public var meetingPoint: Coordinate
    public var notes: String
    public var maxPeople: Int?
    public var hostId: Photographer.ID
    public var attendeeIds: [Photographer.ID]
    public var visibility: Visibility

    public init(
        id: UUID = UUID(),
        cityId: String,
        spotId: String? = nil,
        title: String,
        startsAt: Date,
        duration: TimeInterval,
        meetingPoint: Coordinate,
        notes: String = "",
        maxPeople: Int? = nil,
        hostId: Photographer.ID,
        attendeeIds: [Photographer.ID] = [],
        visibility: Visibility = .private
    ) {
        self.id = id
        self.cityId = cityId
        self.spotId = spotId
        self.title = title
        self.startsAt = startsAt
        self.duration = duration
        self.meetingPoint = meetingPoint
        self.notes = notes
        self.maxPeople = maxPeople
        self.hostId = hostId
        self.attendeeIds = attendeeIds
        self.visibility = visibility
    }

    public var endsAt: Date { startsAt.addingTimeInterval(duration) }

    /// The host counts against the cap: a walk for four means four people
    /// including whoever proposed it.
    public var isFull: Bool {
        guard let maxPeople else { return false }
        return attendeeIds.count + 1 >= maxPeople
    }

    public func isUpcoming(at moment: Date) -> Bool { endsAt > moment }

    public var isValid: Bool {
        !cityId.isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && duration > 0
            && meetingPoint.isValid
            && (maxPeople.map { $0 >= 1 } ?? true)
            && !attendeeIds.contains(hostId)
    }
}
