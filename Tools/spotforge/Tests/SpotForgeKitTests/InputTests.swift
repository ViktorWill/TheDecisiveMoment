import Foundation
import Testing
import TDMCore
@testable import SpotForgeKit

@Suite("YAML subset")
struct YAMLTests {
    @Test("Block mappings, flow mappings and sequences all parse")
    func parsesTheShapesTheDataFilesUse() throws {
        let value = try YAML.parse("""
        - id: us-nyc
          name: New York City
          bbox: { minLat: 40.1, minLon: -74.2, maxLat: 40.9, maxLon: -73.7 }
          tags: [village, bars]
          districts:
            - { name: Manhattan, bbox: { minLat: 1, minLon: 2, maxLat: 3, maxLon: 4 } }
        """)

        let city = try #require(value.sequenceValue?.first)
        #expect(city["id"]?.stringValue == "us-nyc")
        #expect(city["bbox"]?["maxLat"]?.doubleValue == 40.9)
        #expect(city["tags"]?.sequenceValue?.compactMap(\.stringValue) == ["village", "bars"])
        #expect(city["districts"]?.sequenceValue?.count == 1)
        #expect(city["districts"]?.sequenceValue?.first?["name"]?.stringValue == "Manhattan")
    }

    @Test("Folded and literal scalars keep the text the writer meant")
    func parsesBlockScalars() throws {
        let value = try YAML.parse("""
        folded: >
          one
          two
        literal: |
          one
          two
        """)

        #expect(value["folded"]?.stringValue == "one two")
        #expect(value["literal"]?.stringValue == "one\ntwo")
    }

    @Test("Comments and quoted scalars")
    func handlesCommentsAndQuotes() throws {
        let value = try YAML.parse("""
        # leading comment
        note: "a # inside quotes stays"   # trailing comment
        empty:
        """)

        #expect(value["note"]?.stringValue == "a # inside quotes stays")
        #expect(value["empty"]?.stringValue == "")
    }

    @Test("A duplicate key is an error rather than a silent overwrite")
    func rejectsDuplicateKeys() {
        #expect(throws: YAMLError.self) {
            try YAML.parse("""
            a: 1
            a: 2
            """)
        }
    }
}

@Suite("City catalog")
struct CityCatalogTests {
    @Test("The fixture city parses")
    func parsesFixtureCity() throws {
        let catalog = try CityCatalog.load(contentsOf: Fixtures.citiesPath)
        let city = try catalog.city(withId: "us-nyc")
        #expect(city.name == "New York City")
        #expect(city.country == "US")
        #expect(city.bbox.contains(Coordinate(latitude: 40.7305, longitude: -73.997)))
        // No districts declared, so the city bbox is the single query box.
        #expect(city.queryBoxes.count == 1)
    }

    @Test("The shipped data/cities.yml declares us-nyc with its five boroughs")
    func parsesShippedCatalog() throws {
        let path = Fixtures.repositoryRoot.appendingPathComponent("data/cities.yml").path
        let catalog = try CityCatalog.load(contentsOf: path)
        let city = try catalog.city(withId: "us-nyc")
        #expect(city.districts.count == 5)
        #expect(city.districts.map(\.name).contains("Brooklyn"))
        // Every district has to sit inside the city box or the sweep misses it.
        for district in city.districts {
            #expect(city.bbox.contains(district.bbox.center))
        }
        #expect(city.queryBoxes.count == 5)
    }

    @Test("An unknown city id names itself in the error")
    func reportsUnknownCity() throws {
        let catalog = try CityCatalog.load(contentsOf: Fixtures.citiesPath)
        #expect(throws: CityCatalogError.self) { try catalog.city(withId: "fr-paris") }
    }
}

@Suite("Curated canon")
struct CuratedSourceTests {
    @Test("The fixture canon parses with slugs, boosts and notes")
    func parsesFixtureCanon() async throws {
        let source = CuratedSource(cityId: "us-nyc", directory: Fixtures.curatedDirectory)
        let spots = try await source.fetch(bbox: Fixtures.bbox)

        #expect(spots.count == 2)
        let square = try #require(spots.first { $0.sourceId.hasSuffix("washington-square") })
        #expect(square.id == "curated:us-nyc/washington-square")
        #expect(square.kind == .plaza)
        #expect(square.curationBoost == 0.30)
        #expect(square.note?.hasPrefix("The fountain basin") == true)
        #expect(square.refs["curated"] == "us-nyc/washington-square")

        // The second entry has no explicit slug, so one is derived from the name.
        let macdougal = try #require(spots.first { $0.kind == .intersection })
        #expect(macdougal.sourceId == "us-nyc/macdougal-street-west-4th")
        #expect(macdougal.streetBearing == 30)
        #expect(macdougal.bestHours == [20, 21, 22])
    }

    @Test("The shipped NYC canon has at least eight usable entries")
    func shippedCanonIsUsable() async throws {
        let directory = Fixtures.repositoryRoot.appendingPathComponent("data/curated").path
        let source = CuratedSource(cityId: "us-nyc", directory: directory, isOptional: false)
        let path = Fixtures.repositoryRoot.appendingPathComponent("data/cities.yml").path
        let city = try CityCatalog.load(contentsOf: path).city(withId: "us-nyc")

        let spots = try await source.fetch(bbox: city.bbox)
        #expect(spots.count >= 8)
        #expect(Set(spots.map(\.sourceId)).count == spots.count)
        for spot in spots {
            #expect(spot.coordinate.isValid)
            #expect(!spot.name.isEmpty)
            #expect(spot.curationBoost > 0)
            #expect(city.bbox.contains(spot.coordinate))
        }
    }

    @Test("Two entries that reduce to the same slug are a build error")
    func rejectsDuplicateSlugs() {
        #expect(throws: CuratedError.self) {
            try CuratedSource.parse(
                """
                - name: Union Square
                  lat: 40.7359
                  lon: -73.9911
                - name: union square
                  lat: 40.7360
                  lon: -73.9912
                """,
                cityId: "us-nyc"
            )
        }
    }

    @Test("A missing optional canon is empty, a missing required one throws")
    func handlesMissingFiles() async throws {
        let optional = CuratedSource(cityId: "gb-lon", directory: Fixtures.curatedDirectory)
        let none = try await optional.fetch(bbox: Fixtures.bbox)
        #expect(none.isEmpty)

        let required = CuratedSource(cityId: "gb-lon", directory: Fixtures.curatedDirectory, isOptional: false)
        await #expect(throws: CuratedError.self) { try await required.fetch(bbox: Fixtures.bbox) }
    }
}
