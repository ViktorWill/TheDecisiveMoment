import Foundation
import TDMCore
import TDMLight

/// A spot handed from the Map tab to the Light tab.
///
/// Everything the Light screen needs to answer *for this place*: where it is,
/// which way the street runs, and how much sky it can see. Carried as a value
/// so the two screens share no state beyond the moment of the tap.
public struct SpotHandoff: Sendable, Hashable, Identifiable {
    public var spotId: String
    public var name: String
    public var coordinate: Coordinate
    /// Degrees clockwise from north, `nil` when the bundle does not carry one.
    public var streetBearingDegrees: Double?
    public var scene: ScenePreset

    public var id: String { spotId }

    public init(
        spotId: String,
        name: String,
        coordinate: Coordinate,
        streetBearingDegrees: Double?,
        scene: ScenePreset
    ) {
        self.spotId = spotId
        self.name = name
        self.coordinate = coordinate
        self.streetBearingDegrees = streetBearingDegrees
        self.scene = scene
    }

    public init(spot: Spot) {
        self.init(
            spotId: spot.id,
            name: spot.name,
            coordinate: spot.coordinate,
            streetBearingDegrees: spot.streetBearing,
            scene: Self.scene(for: spot.openness)
        )
    }

    /// `openness` is carried in the bundle precisely so that selecting a spot
    /// pre-fills the scene modifier without the user describing the street —
    /// `docs/EXPOSURE-MODEL.md` §4c.
    public static func scene(for openness: Openness) -> ScenePreset {
        switch openness {
        case .open: .openSky
        case .canyon: .narrowCanyon
        case .covered: .underArcade
        }
    }
}
