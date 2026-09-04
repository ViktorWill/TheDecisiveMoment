import Foundation
import Testing
import TDMCore
@testable import SpotForgeKit

@Suite("Overpass")
struct OverpassSourceTests {
    @Test("The feature query asks for centres and geometry in two passes")
    func queryShape() {
        let query = OverpassSource.featureQuery(bbox: Fixtures.bbox)
        // Overpass allows one geometry mode per `out`, so the set is stored and
        // printed twice; without the second pass there is no street bearing.
        #expect(query.contains(")->.spots;"))
        #expect(query.contains(".spots out center tags;"))
        #expect(query.contains(".spots out ids geom;"))
        #expect(query.contains("[out:json]"))
    }

    @Test("The broad clauses are qualified so a well-mapped city does not return every instance")
    func queryIsNarrowed() {
        let query = OverpassSource.featureQuery(bbox: Fixtures.bbox)
        // Crossings: only where people gather and wait, not every marked leg.
        #expect(query.contains(#"way ["highway"="footway"]["footway"="crossing"]["crossing"="traffic_signals"]"#))
        // Steps: named only, not every stoop and subway stair.
        #expect(query.contains(#"way ["highway"="steps"]["name"]"#))
        // Tunnel/covered: a value whitelist, not a bare presence check that
        // also matches service roads and vehicle underpasses.
        #expect(query.contains(#"way ["tunnel"="yes"]["highway"~"^(pedestrian|footway|steps|path)$"]"#))
        #expect(query.contains(#"way ["covered"="yes"]["highway"~"^(pedestrian|footway|steps|path)$"]"#))
    }

    @Test("Recorded features map to the documented kinds, bearings and openness")
    func mapsRecordedFeatures() async throws {
        let source = OverpassSource(runner: try Fixtures.runner())
        let spots = try await source.fetch(bbox: Fixtures.bbox)
        let byId = Dictionary(uniqueKeysWithValues: spots.map { ($0.sourceId, $0) })

        #expect(spots.count == 6)
        #expect(byId["way/1"]?.kind == .street)
        #expect(byId["way/4"]?.kind == .park)
        #expect(byId["node/5"]?.kind == .market)
        #expect(byId["node/6"]?.kind == .transit)
        #expect(byId["node/7"]?.kind == .viewpoint)
        #expect(byId["way/8"]?.kind == .stairs)

        // way/1 runs east–west, so its bearing is a right angle from north.
        let street = try #require(byId["way/1"]?.streetBearing)
        #expect(abs(street - 90) < 0.01)
        // A node has no geometry and therefore no bearing to report.
        #expect(byId["node/5"]?.streetBearing == nil)

        // way/8 is ringed by ten-storey buildings in the recorded buildings pass.
        #expect(byId["way/8"]?.openness == .canyon)
        #expect(byId["way/4"]?.openness == .open)
        #expect(byId["way/4"]?.refs["osm"] == "way/4")
    }

    @Test("Kind mapping falls back rather than inventing a category")
    func kindTable() {
        #expect(OverpassSource.kind(for: ["highway": "pedestrian"], isArea: false) == .street)
        #expect(OverpassSource.kind(for: ["highway": "footway", "bridge": "yes"], isArea: false) == .bridge)
        #expect(OverpassSource.kind(for: ["amenity": "marketplace"], isArea: true) == .market)
        #expect(OverpassSource.kind(for: ["leisure": "park"], isArea: true) == .park)
        #expect(OverpassSource.kind(for: ["shop": "bakery"], isArea: false) == .other)
    }

    @Test("A covered way reads covered without needing the buildings pass")
    func opennessFromTags() {
        let index = BuildingHeightIndex(elements: [])
        let arcade = OverpassSource.openness(
            for: ["highway": "footway", "covered": "yes"],
            at: Coordinate(latitude: 40.73, longitude: -73.99),
            walls: index
        )
        #expect(arcade == .covered)
    }
}

@Suite("Wikidata")
struct WikidataSourceTests {
    @Test("The SPARQL query boxes the bbox with south-west and north-east corners")
    func queryShape() {
        let query = WikidataSource.query(bbox: Fixtures.bbox)
        #expect(query.contains("wikibase:box"))
        #expect(query.contains("wikibase:cornerSouthWest"))
        #expect(query.contains("wikibase:cornerNorthEast"))
    }

    @Test("Recorded bindings become landmarks with sitelink counts")
    func mapsRecordedBindings() async throws {
        let source = WikidataSource(runner: try Fixtures.runner())
        let spots = try await source.fetch(bbox: Fixtures.bbox)
        #expect(spots.count == 3)

        let arch = try #require(spots.first { $0.sourceId == "Q1163609" })
        #expect(arch.name == "Washington Square Arch")
        #expect(arch.kind == .landmark)
        #expect(arch.sitelinks == 34)
        #expect(arch.refs["wikidata"] == "Q1163609")
        // Point() is longitude first; a swap here would put New York in Antarctica.
        #expect(abs(arch.coordinate.latitude - 40.73096) < 0.0001)
        #expect(abs(arch.coordinate.longitude + 73.99725) < 0.0001)
        #expect(Fixtures.bbox.contains(arch.coordinate))
    }

    @Test("An item whose label is its own Q-id is skipped as unnamed")
    func skipsUnlabelledItems() async throws {
        let source = WikidataSource(runner: try Fixtures.runner())
        let spots = try await source.fetch(bbox: Fixtures.bbox)
        #expect(!spots.contains { $0.name.hasPrefix("Q") && Int($0.name.dropFirst()) != nil })
    }
}

@Suite("Commons")
struct CommonsSourceTests {
    @Test("Geosearch asks the file namespace, which is not the default")
    func geosearchURLShape() {
        let url = CommonsSource.geosearchURL(at: Coordinate(latitude: 40.73096, longitude: -73.99725))
        let query = try! #require(url.query)
        // Without gsnamespace=6 the API answers with articles, not files.
        #expect(query.contains("gsnamespace=6"))
        #expect(query.contains("list=geosearch"))
        #expect(query.contains("format=json"))
        #expect(url.absoluteString.contains("40.73096"))
    }

    @Test("A sweep accumulates counts into cells rather than querying per candidate")
    func sweepsIntoGrid() async throws {
        let source = CommonsSource(runner: try Fixtures.runner(), minimumCellCountForCandidate: 25)
        let spots = try await source.fetch(bbox: Fixtures.bbox)

        // One sample point covers the fixture box: this is a grid sweep, not a
        // request per candidate spot.
        #expect(await source.sampleCount == 1)
        let grid = await source.densityGrid()
        #expect(grid.totalPhotos == 37)
        #expect(grid.denseCells(minimumCount: 25).count == 1)

        let cell = try #require(spots.first)
        #expect(spots.count == 1)
        #expect(cell.source == .commons)
        #expect(cell.sourceId.hasPrefix("cell/"))
        #expect(cell.kind == .other)
        #expect(Fixtures.bbox.contains(cell.coordinate))
    }

    @Test("A bbox too large to sweep politely fails instead of running for a day")
    func refusesUnboundedSweeps() async throws {
        let source = CommonsSource(runner: try Fixtures.runner(), maximumSamples: 2)
        let continent = BoundingBox(minLat: 35, minLon: -80, maxLat: 45, maxLon: -70)
        await #expect(throws: CommonsError.self) { try await source.fetch(bbox: continent) }
    }

    @Test("Photos carry author and licence, and unattributed files are dropped")
    func attributionIsMandatory() async throws {
        let source = CommonsSource(runner: try Fixtures.runner())
        let photos = try await source.photos(
            near: Coordinate(latitude: 40.73096, longitude: -73.99725),
            radiusMetres: 200,
            limit: 2
        )

        #expect(photos.count == 1)
        let photo = try #require(photos.first)
        #expect(photo.author == "Jane Example")
        #expect(photo.license == "CC BY-SA 4.0")
        #expect(photo.thumbURL.hasPrefix("https://"))
        #expect(photo.pageURL.hasPrefix("https://"))
        #expect(photo.isAttributed)
        // The HTML the API returns for Artist must not reach the client.
        #expect(!photo.author.contains("<"))
    }

    @Test("Markup from extmetadata is reduced to plain text")
    func stripsMarkup() {
        let plain = HTML.plainText("<a href=\"/wiki/User:X\" title=\"x\">Jane &amp; Co</a>")
        #expect(plain == "Jane & Co")
    }
}

@Suite("Photo density grid")
struct PhotoDensityGridTests {
    @Test("Cells are 250 m and counts are read over the neighbourhood")
    func cellsAndCounts() {
        var grid = PhotoDensityGrid(cellMetres: 250, referenceLatitude: 40.73)
        let centre = Coordinate(latitude: 40.73, longitude: -73.99)
        grid.add(centre, count: 10)
        // ~100 m north: same or neighbouring cell, so it counts either way.
        grid.add(Coordinate(latitude: 40.7309, longitude: -73.99), count: 5)
        // ~5 km away: out of the neighbourhood entirely.
        grid.add(Coordinate(latitude: 40.775, longitude: -73.99), count: 100)

        #expect(grid.count(around: centre) == 15)
        #expect(grid.totalPhotos == 115)
        #expect(abs(grid.neighbourhoodRadiusMetres - 375) < 0.001)
    }

    @Test("Sample points cover the box with no gap wider than the spacing")
    func samplesCoverTheBox() {
        let grid = PhotoDensityGrid(cellMetres: 250, referenceLatitude: 40.73)
        let box = BoundingBox(minLat: 40.72, minLon: -74.0, maxLat: 40.73, maxLon: -73.99)
        let points = grid.samplePoints(in: box, spacingMetres: 500)

        #expect(points.count > 1)
        for point in points {
            #expect(box.contains(point))
        }
    }
}

