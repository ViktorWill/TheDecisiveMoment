#if canImport(SwiftData)
import Foundation
import SwiftData
import TDMCore

/// A ``ShootSession`` as stored.
///
/// Flat columns rather than a JSON blob, because the list is queried by start
/// time and by city, and because phase 3's tables have these same columns —
/// a blob now would be a migration later.
@Model
public final class StoredShootSession {
    @Attribute(.unique) public var id: UUID = UUID()
    public var cityId: String = ""
    /// The map anchor, when there is one. A plain id, not a relationship: the
    /// spot may live in a bundle that a refresh replaces, and a session must
    /// outlive that.
    public var spotId: String?
    public var title: String = ""
    public var startsAt: Date = Date.distantPast
    public var duration: TimeInterval = 0
    public var lat: Double = 0
    public var lon: Double = 0
    public var notes: String = ""
    public var maxPeople: Int?
    public var hostId: UUID = UUID()
    public var attendeeIds: [UUID] = []
    public var visibilityRawValue: String = Visibility.private.rawValue

    public init(_ session: ShootSession) {
        id = session.id
        apply(session)
    }

    public func apply(_ session: ShootSession) {
        cityId = session.cityId
        spotId = session.spotId
        title = session.title
        startsAt = session.startsAt
        duration = session.duration
        lat = session.meetingPoint.latitude
        lon = session.meetingPoint.longitude
        notes = session.notes
        maxPeople = session.maxPeople
        hostId = session.hostId
        attendeeIds = session.attendeeIds
        visibilityRawValue = session.visibility.rawValue
    }

    public var value: ShootSession {
        ShootSession(
            id: id,
            cityId: cityId,
            spotId: spotId,
            title: title,
            startsAt: startsAt,
            duration: duration,
            meetingPoint: Coordinate(latitude: lat, longitude: lon),
            notes: notes,
            maxPeople: maxPeople,
            hostId: hostId,
            attendeeIds: attendeeIds,
            visibility: Visibility(rawValue: visibilityRawValue) ?? .private
        )
    }
}

/// The local photographer. One row: v1 has no accounts, so there is exactly one
/// person on the device and they are the host of everything they plan.
@Model
public final class StoredPhotographer {
    @Attribute(.unique) public var id: UUID = UUID()
    public var displayName: String = Photographer.defaultDisplayName
    public var gearSummary: String?
    public var bio: String?
    public var cities: [String] = []

    public init(_ photographer: Photographer) {
        id = photographer.id
        apply(photographer)
    }

    public func apply(_ photographer: Photographer) {
        displayName = photographer.displayName
        gearSummary = photographer.gearSummary
        bio = photographer.bio
        cities = photographer.cities
    }

    public var value: Photographer {
        Photographer(
            id: id,
            displayName: displayName,
            gearSummary: gearSummary,
            bio: bio,
            cities: cities
        )
    }
}
#endif
