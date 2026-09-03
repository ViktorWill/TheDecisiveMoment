import Foundation
import TDMCore

/// The user's own pins: how they are identified, and how one is made.
///
/// Ids are `local:{uuid}` so that a pin can never collide with a bundle id, and
/// so that a store can tell at a glance which rows a bundle refresh may replace
/// — the pins have to survive it (`docs/SPEC-map.md`, "Your own pins").
public enum LocalPin {
    public static let idPrefix = "local:"

    public static func makeID(uuid: UUID = UUID()) -> String {
        idPrefix + uuid.uuidString.lowercased()
    }

    public static func isLocal(id: String) -> Bool {
        id.hasPrefix(idPrefix) && id.count > idPrefix.count
    }

    /// A dropped pin.
    ///
    /// Score is `1` because the user chose to stand there: a pin the score floor
    /// could hide would be a pin that vanished for no reason the user can see.
    /// It is `curated: false` all the same — `curated` means a human wrote the
    /// *bundle* entry, and the map's curated colour is about provenance.
    public static func make(
        id: String = makeID(),
        name: String,
        coordinate: Coordinate,
        kind: SpotKind = .street,
        openness: Openness = .open,
        tags: [String] = [],
        note: String? = nil,
        streetBearingDegrees: Double? = nil
    ) -> Spot {
        Spot(
            id: id,
            name: name,
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            kind: kind,
            sources: [.local],
            score: 1,
            scoreFactors: [],
            tags: tags,
            bestHours: nil,
            streetBearing: streetBearingDegrees.map(normalisedAxisBearing),
            openness: openness,
            note: note,
            refs: [:],
            photos: [],
            curated: false
        )
    }

    /// A street is an axis, so a bearing is folded into 0…180 — the range
    /// `Spot.isValid` accepts. A heading of 200° and one of 20° are the same
    /// street, and only one of them is storable.
    public static func normalisedAxisBearing(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 180)
        return wrapped < 0 ? wrapped + 180 : wrapped
    }
}
