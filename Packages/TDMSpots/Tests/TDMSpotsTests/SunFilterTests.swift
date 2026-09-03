import Foundation
import Testing
import TDMCore
@testable import TDMSpots

@Suite("Lit now — SPEC-map.md")
struct SunFilterTests {
    static func spot(
        openness: Openness,
        streetBearing: Double? = nil,
        id: String = "osm:1"
    ) -> Spot {
        Spot(
            id: id, name: "A street", lat: 40.73, lon: -73.99, kind: .street, sources: [.osm],
            score: 0.5, streetBearing: streetBearing, openness: openness
        )
    }

    @Test("Nothing is lit after sunset")
    func nothingIsLitBelowTheHorizon() {
        let sun = SunFilter(azimuthDegrees: 285, elevationDegrees: -2)

        #expect(!sun.isLit(Self.spot(openness: .open)))
        #expect(!sun.isLit(Self.spot(openness: .canyon, streetBearing: 15)))
        #expect(!sun.isDaylight)
    }

    @Test("An open spot is lit whenever the sun is up")
    func openSpotsFollowTheHorizon() {
        let sun = SunFilter(azimuthDegrees: 120, elevationDegrees: 3)

        #expect(sun.isLit(Self.spot(openness: .open)))
    }

    @Test("A covered spot is never in direct sun")
    func coveredSpotsAreNeverLit() {
        let noon = SunFilter(azimuthDegrees: 180, elevationDegrees: 70)

        #expect(!noon.isLit(Self.spot(openness: .covered)))
    }

    @Test("A canyon is lit when the sun runs down its axis")
    func canyonAlongAxis() {
        // Manhattan's grid runs 29° east of north; the sun at 205° is 4° off the
        // axis, which is the Manhattanhenge case.
        let sun = SunFilter(azimuthDegrees: 205, elevationDegrees: 12)

        #expect(sun.isLit(Self.spot(openness: .canyon, streetBearing: 29)))
    }

    @Test("A canyon across the sun is in shadow until the sun clears the wall")
    func canyonAcrossTheSun() {
        let low = SunFilter(azimuthDegrees: 119, elevationDegrees: 12)
        let high = SunFilter(azimuthDegrees: 119, elevationDegrees: 52)
        let acrossTheGrid = Self.spot(openness: .canyon, streetBearing: 29)

        #expect(!low.isLit(acrossTheGrid))
        #expect(high.isLit(acrossTheGrid))
    }

    @Test("A canyon with no bearing needs the sun above the walls")
    func canyonWithoutBearing() {
        #expect(!SunFilter(azimuthDegrees: 100, elevationDegrees: 20).isLit(Self.spot(openness: .canyon)))
        #expect(SunFilter(azimuthDegrees: 100, elevationDegrees: 60).isLit(Self.spot(openness: .canyon)))
    }

    @Test("A street is an axis, so the offset folds into 0…90°")
    func axisOffsetFolds() {
        #expect(SunFilter.axisOffset(azimuthDegrees: 205, streetBearingDegrees: 29) == 4)
        #expect(SunFilter.axisOffset(azimuthDegrees: 25, streetBearingDegrees: 29) == 4)
        #expect(SunFilter.axisOffset(azimuthDegrees: 119, streetBearingDegrees: 29) == 90)
        #expect(SunFilter.axisOffset(azimuthDegrees: 350, streetBearingDegrees: 10) == 20)
    }

    @Test("The pill filters a mixed region")
    func filterAppliesToQuery() {
        let spots = [
            Self.spot(openness: .open, id: "osm:open"),
            Self.spot(openness: .covered, id: "osm:covered"),
            Self.spot(openness: .canyon, streetBearing: 29, id: "osm:aligned"),
            Self.spot(openness: .canyon, streetBearing: 119, id: "osm:across")
        ]
        let query = SpotQuery(sunlight: SunFilter(azimuthDegrees: 205, elevationDegrees: 12))

        #expect(SpotFilter.apply(query, to: spots).map(\.id) == ["osm:aligned", "osm:open"])
    }

    @Test("Shade is not waived for curated spots")
    func curationDoesNotOverrideShade() {
        let curated = Spot(
            id: "curated:1", name: "Arcade", lat: 40.73, lon: -73.99, kind: .arcade,
            sources: [.curated], score: 0.9, openness: .covered, curated: true
        )
        let query = SpotQuery(
            minimumScore: 0.3,
            alwaysIncludeCurated: true,
            sunlight: SunFilter(azimuthDegrees: 180, elevationDegrees: 40)
        )

        #expect(SpotFilter.apply(query, to: [curated]).isEmpty)
    }
}
