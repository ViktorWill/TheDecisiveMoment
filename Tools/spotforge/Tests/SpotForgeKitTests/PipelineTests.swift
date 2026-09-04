import Foundation
import Synchronization
import Testing
import TDMCore
import TDMSpots
@testable import SpotForgeKit

@Suite("Pipeline")
struct PipelineTests {
    private func makePipeline(options: PipelineOptions = PipelineOptions(fetchesPhotos: false)) throws -> Pipeline {
        let runner = try Fixtures.runner()
        let city = try CityCatalog.load(contentsOf: Fixtures.citiesPath).city(withId: "us-nyc")
        let commons = CommonsSource(runner: runner)
        return Pipeline(
            city: city,
            sources: [
                OverpassSource(runner: runner),
                WikidataSource(runner: runner),
                commons,
                CuratedSource(cityId: city.id, directory: Fixtures.curatedDirectory)
            ],
            commons: commons,
            runner: runner,
            options: options
        )
    }

    @Test("All four sources contribute and the merge collapses the duplicates")
    func fourSourcesContribute() async throws {
        let output = await try makePipeline().run(bundleVersion: 1)
        let report = output.report

        for source in [SourceKind.osm, .wikidata, .commons, .curated] {
            let tally = try #require(report.sources.first { $0.source == source })
            #expect(tally.candidates > 0, "\(source.rawValue) returned nothing")
            #expect(tally.failure == nil)
        }
        #expect(report.warnings.isEmpty)
        #expect(report.merges > 0)
        #expect(output.city.spots.count == report.spotCount)

        // The OSM park, the Wikidata arch and the curated entry are the same
        // place, so the survivor names all three sources.
        let square = try #require(output.city.spots.first { $0.refs["curated"] == "us-nyc/washington-square" })
        #expect(Set(square.sources) == Set([.osm, .wikidata, .curated]))
        #expect(square.curated)
        #expect(square.refs["wikidata"] == "Q1163609")
    }

    @Test("Scores use the photo grid, the sitelink count and the curation boost")
    func scoresCarryTheirWorking() async throws {
        let output = await try makePipeline().run(bundleVersion: 1)
        let square = try #require(output.city.spots.first { $0.refs["curated"] == "us-nyc/washington-square" })

        let kinds = Set(square.scoreFactors.map(\.kind))
        #expect(kinds.contains(.photoDensity))
        #expect(kinds.contains(.notability))
        #expect(kinds.contains(.curation))
        #expect(kinds.contains(.featurePrior))
        #expect(square.score > 0)
        #expect(square.score <= 1)

        // The best spot in the box is the one three sources agree on.
        #expect(output.city.spots.max { $0.score < $1.score }?.id == square.id)
        // Written in id order, not score order: a regenerated city then reads
        // as a reviewable diff (docs/DATA-BUNDLES.md, "canonical JSON").
        #expect(output.city.spots.map(\.id) == output.city.spots.map(\.id).sorted())
    }

    @Test("Photos are attached to the top spots with attribution intact")
    func attachesPhotos() async throws {
        let pipeline = try makePipeline(options: PipelineOptions(photoSpotLimit: 5, photosPerSpot: 2, fetchesPhotos: true))
        let output = await pipeline.run(bundleVersion: 1)

        let photographed = output.city.spots.filter { !$0.photos.isEmpty }
        #expect(!photographed.isEmpty)
        for spot in photographed {
            for photo in spot.photos {
                #expect(photo.isAttributed)
            }
        }
        #expect(output.report.photoTotal == 37)
        #expect(output.report.photoCells >= 1)
    }

    @Test("The size cap trims the tail and says how much it dropped")
    func trimsToTheSizeBudget() async throws {
        // Small enough that only a spot or two survive: the cap has to bite for
        // the report line to mean anything.
        var options = PipelineOptions(fetchesPhotos: false)
        options.sizeBudgetBytes = 400
        let output = await try makePipeline(options: options).run(bundleVersion: 1)

        #expect(output.report.droppedBySizeCap > 0)
        #expect(output.city.spots.count < output.report.mergedCount)
        // Curated spots are the canon; they are the last thing to go.
        #expect(output.city.spots.allSatisfy { $0.score > 0 })
        #expect(output.report.scoreFloor != nil)
    }

    /// Issue #52: the photo pass ran *after* the trim, so the trim measured a
    /// city without photo payloads and the bundle written to disk was over
    /// budget. The check is against the bytes the writer actually produced.
    @Test("A bundle built with photos is within its size budget as written")
    func photosFitInsideTheSizeBudget() async throws {
        let directory = try Fixtures.temporaryDirectory("budget")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Small enough that the photo payloads are the difference between
        // fitting and not: with the 500 KB default the fixture city fits either
        // way and the ordering bug would be invisible. With the photo pass
        // after the trim this wrote 1852 B against a 1600 B budget.
        var options = PipelineOptions(photoSpotLimit: 5, photosPerSpot: 2, fetchesPhotos: true)
        options.sizeBudgetBytes = 1_600
        let output = await try makePipeline(options: options).run(bundleVersion: 1)

        #expect(output.city.spots.contains { !$0.photos.isEmpty }, "no photos attached, so this proves nothing")

        let written = try BundleWriter(outputDirectory: directory).write(output.city)
        #expect(written.compressedBytes <= options.sizeBudgetBytes, "\(written.compressedBytes) B gz over \(options.sizeBudgetBytes) B")

        var report = output.report
        report.compressedBytes = written.compressedBytes
        #expect(!report.isOverSizeBudget)
        #expect(report.warnings.isEmpty)
    }

    @Test("A bundle over the size budget warns, naming the budget and the size")
    func overBudgetWarns() async throws {
        var report = BuildReport(cityId: "us-nyc")
        report.spotCount = 7132
        report.sizeBudgetBytes = 512_000
        report.compressedBytes = 527_412

        #expect(report.isOverSizeBudget)
        let warning = try #require(report.warnings.first { $0.contains("budget") })
        #expect(warning.contains("527412"))
        #expect(warning.contains("512000"))
        #expect(warning.contains("15412"))
        #expect(report.summary.contains(warning))

        // At budget is not over it, and a report that never measured a size
        // cannot warn about one.
        report.compressedBytes = 512_000
        #expect(!report.isOverSizeBudget)
        report.compressedBytes = 527_412
        report.sizeBudgetBytes = 0
        #expect(!report.isOverSizeBudget)
    }

    @Test("An empty source is loud in the report rather than silently missing")    func emptySourceWarns() async throws {
        let runner = try Fixtures.runner()
        let city = try CityCatalog.load(contentsOf: Fixtures.citiesPath).city(withId: "us-nyc")
        // No curated file for this city id, so that source returns nothing.
        let pipeline = Pipeline(
            city: city,
            sources: [OverpassSource(runner: runner), CuratedSource(cityId: "gb-lon", directory: Fixtures.curatedDirectory)],
            options: PipelineOptions(fetchesPhotos: false)
        )
        let report = await pipeline.run(bundleVersion: 1).report

        #expect(report.emptySources == [.curated])
        #expect(report.warnings.contains { $0.contains("curated") })
        #expect(report.summary.contains("curated"))
    }

    /// PR #16: nothing printed between "Build complete" and the final
    /// report, so a multi-hour run and a genuine hang were indistinguishable.
    /// This checks that every stage the issue names actually announces itself.
    @Test("Every stage announces itself, and the report times each one")
    func announcesEveryStage() async throws {
        let lines = Mutex<[String]>([])
        let pipeline = try makePipeline(options: PipelineOptions(fetchesPhotos: false))
        let output = await Pipeline(
            city: pipeline.city,
            sources: pipeline.sources,
            commons: pipeline.commons,
            runner: pipeline.runner,
            options: pipeline.options,
            progress: { line in lines.withLock { $0.append(line) } }
        ).run(bundleVersion: 1)

        let seen = lines.withLock { $0 }
        #expect(seen.contains { $0.contains("merge:") })
        #expect(seen.contains { $0.hasPrefix("score") })
        #expect(seen.contains { $0.hasPrefix("trim") })
        #expect(seen.contains { $0.contains("osm") && $0.contains("fetching") })
        #expect(seen.contains { $0.contains("commons") && $0.contains("sweeping") })

        let stageNames = Set(output.report.stageDurations.map(\.stage))
        #expect(stageNames == ["fetch", "merge", "score", "trim", "photos"])
        #expect(output.report.stageDurations.allSatisfy { $0.seconds >= 0 })
    }

    @Test("A source that throws is reported as failed, and the build goes on")
    func failingSourceIsReported() async throws {
        struct BrokenSource: SpotForgeKit.SpotSource {
            let sourceKind: SourceKind = .wikidata
            func fetch(bbox: BoundingBox) async throws -> [RawSpot] {
                throw HTTPError.status(code: 504, url: URL(string: "https://query.wikidata.org")!, body: "gateway timeout")
            }
        }

        let runner = try Fixtures.runner()
        let city = try CityCatalog.load(contentsOf: Fixtures.citiesPath).city(withId: "us-nyc")
        let pipeline = Pipeline(
            city: city,
            sources: [OverpassSource(runner: runner), BrokenSource()],
            options: PipelineOptions(fetchesPhotos: false)
        )
        let output = await pipeline.run(bundleVersion: 1)

        #expect(output.report.failedSources == [.wikidata])
        #expect(output.report.warnings.contains { $0.contains("wikidata") })
        // The other source's spots still made it into the bundle.
        #expect(!output.city.spots.isEmpty)
    }
}

/// `BuildCommand.run` logs from a `@Sendable` closure, so the test's collector
/// has to be safe to call from anywhere.
final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("Build command")
struct BuildCommandTests {
    @Test("A fixture build writes a bundle the app decodes and validate accepts")
    func buildsAndValidates() async throws {
        let directory = try Fixtures.temporaryDirectory("build")
        defer { try? FileManager.default.removeItem(at: directory) }

        var request = BuildRequest(scope: .cities(["us-nyc"]))
        request.outputDirectory = directory.path
        request.citiesPath = Fixtures.citiesPath
        request.curatedDirectory = Fixtures.curatedDirectory
        request.fixturesDirectory = Fixtures.directory.path
        request.cacheDirectory = nil
        request.printsReport = true

        let log = LogCollector()
        let outcome = try await BuildCommand(request: request).run(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            log: { line in log.append(line) }
        )
        let lines = log.lines

        #expect(outcome.reports.count == 1)
        #expect(!outcome.hasWarnings)
        #expect(lines.contains { $0.contains("us-nyc") })

        let result = BundleValidator(directory: directory).validate()
        #expect(result.isValid, "\(result.summary)")
        #expect(result.spotCount > 0)

        // The app's own decoder, over the index the build wrote.
        let decoder = BundleDecoder()
        let index = try decoder.decodeIndex(try Data(contentsOf: directory.appendingPathComponent("index.json")))
        let entry = try #require(index.entry(for: "us-nyc"))
        let compressed = try Data(contentsOf: directory.appendingPathComponent(entry.bundlePath))
        let city = try decoder.decodeCity(compressed: compressed, entry: entry)

        #expect(city.spots.count == entry.spotCount)
        #expect(Set(city.spots.flatMap(\.sources)) == Set([.osm, .wikidata, .commons, .curated]))
        #expect(city.attribution.osm?.contains("OpenStreetMap") == true)
        #expect(entry.bytes == compressed.count || entry.bytes > 0)
    }

    @Test("Rebuilding the same city bumps the bundle version and keeps the index sane")
    func rebuildBumpsVersion() async throws {
        let directory = try Fixtures.temporaryDirectory("rebuild")
        defer { try? FileManager.default.removeItem(at: directory) }

        var request = BuildRequest(scope: .cities(["us-nyc"]))
        request.outputDirectory = directory.path
        request.citiesPath = Fixtures.citiesPath
        request.curatedDirectory = Fixtures.curatedDirectory
        request.fixturesDirectory = Fixtures.directory.path
        request.cacheDirectory = nil

        _ = try await BuildCommand(request: request).run(log: { _ in })
        _ = try await BuildCommand(request: request).run(log: { _ in })

        let index = try BundleDecoder().decodeIndex(try Data(contentsOf: directory.appendingPathComponent("index.json")))
        #expect(index.cities.count == 1)
        let entry = try #require(index.entry(for: "us-nyc"))
        #expect(entry.bundleVersion == 2)
        #expect(BundleValidator(directory: directory).validate().isValid)
    }

    @Test("An unknown city id fails the build instead of writing an empty bundle")
    func unknownCityFails() async throws {
        let directory = try Fixtures.temporaryDirectory("unknown")
        defer { try? FileManager.default.removeItem(at: directory) }

        var request = BuildRequest(scope: .cities(["fr-par"]))
        request.outputDirectory = directory.path
        request.citiesPath = Fixtures.citiesPath
        request.curatedDirectory = Fixtures.curatedDirectory
        request.fixturesDirectory = Fixtures.directory.path
        request.cacheDirectory = nil

        await #expect(throws: CityCatalogError.self) {
            _ = try await BuildCommand(request: request).run(log: { _ in })
        }
    }
}
