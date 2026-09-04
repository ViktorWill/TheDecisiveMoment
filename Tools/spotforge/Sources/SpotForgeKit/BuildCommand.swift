import Foundation
import TDMCore

/// Everything a run was asked to do — `spotforge build …` parsed.
public struct BuildRequest: Sendable {
    public enum Scope: Sendable, Equatable {
        case cities([String])
        case allCities
    }

    public var scope: Scope
    public var outputDirectory: String
    public var citiesPath: String
    public var curatedDirectory: String
    public var cacheDirectory: String?
    /// A directory of recorded responses. When set, nothing touches the
    /// network — which is how the pipeline is exercised end to end in a test.
    public var fixturesDirectory: String?
    public var printsReport: Bool
    /// Turn a source that returned nothing into a failed build. What CI wants.
    public var strict: Bool
    public var fetchesPhotos: Bool

    public init(
        scope: Scope,
        outputDirectory: String = "bundles/v1",
        citiesPath: String = "data/cities.yml",
        curatedDirectory: String = "data/curated",
        cacheDirectory: String? = ".cache",
        fixturesDirectory: String? = nil,
        printsReport: Bool = false,
        strict: Bool = false,
        fetchesPhotos: Bool = true
    ) {
        self.scope = scope
        self.outputDirectory = outputDirectory
        self.citiesPath = citiesPath
        self.curatedDirectory = curatedDirectory
        self.cacheDirectory = cacheDirectory
        self.fixturesDirectory = fixturesDirectory
        self.printsReport = printsReport
        self.strict = strict
        self.fetchesPhotos = fetchesPhotos
    }
}

/// Assembles the four sources and runs the pipeline for each requested city.
public struct BuildCommand: Sendable {
    public var request: BuildRequest

    public init(request: BuildRequest) {
        self.request = request
    }

    public struct Outcome: Sendable {
        public var reports: [BuildReport] = []
        public var indexPath: String = ""

        public var hasWarnings: Bool { reports.contains { !$0.warnings.isEmpty } }
    }

    /// Unconditional progress, one line per notable event — PR #16: a
    /// multi-hour run and a genuine hang look identical without this. Writes
    /// to stderr by default so `--report`'s summary on stdout stays clean.
    public func run(
        now: Date = Date(),
        log: @Sendable (String) -> Void = { print($0) },
        progress: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async throws -> Outcome {
        let catalog = try CityCatalog.load(contentsOf: request.citiesPath)
        let cities: [CityDefinition] = switch request.scope {
        case .allCities: catalog.cities
        case .cities(let ids): try ids.map(catalog.city(withId:))
        }

        let writer = BundleWriter(outputDirectory: URL(fileURLWithPath: request.outputDirectory))
        var outcome = Outcome()
        var entries: [CityIndexEntry] = []

        for city in cities {
            let transport: any Transport = try request.fixturesDirectory.map {
                try RecordedTransport(directory: URL(fileURLWithPath: $0))
            } ?? URLSessionTransport()
            let runner = RequestRunner(
                transport: transport,
                // Recorded runs neither consult nor fill the cache: a test
                // that depended on a previous run's cache would not be a test.
                cacheDirectory: request.fixturesDirectory == nil
                    ? request.cacheDirectory.map { URL(fileURLWithPath: $0) }
                    : nil,
                minimumInterval: request.fixturesDirectory == nil ? 1 : 0,
                // Overpass and WDQS stay serial at the default policy; Commons
                // is a different service with no such restriction, so it gets
                // its own overlap (PR #16).
                namespacePolicies: request.fixturesDirectory == nil
                    ? ["commons": RequestRunner.politeCommonsPolicy]
                    : ["commons": RequestRunner.HostPolicy(concurrency: 3, minimumInterval: 0)]
            )
            let commons = CommonsSource(runner: runner)
            let pipeline = Pipeline(
                city: city,
                sources: [
                    OverpassSource(runner: runner),
                    WikidataSource(runner: runner),
                    commons,
                    CuratedSource(cityId: city.id, directory: request.curatedDirectory)
                ],
                commons: commons,
                runner: runner,
                options: PipelineOptions(fetchesPhotos: request.fetchesPhotos),
                progress: progress
            )

            progress("\(city.id): starting")
            let output = await pipeline.run(
                bundleVersion: writer.nextBundleVersion(for: city.id),
                generatedAt: now
            )
            progress("write: \(output.city.spots.count) spots")
            let writeStarted = Date()
            let written = try writer.write(output.city)
            var report = output.report
            report.jsonBytes = written.jsonBytes
            report.compressedBytes = written.compressedBytes
            report.recordStage("write", since: writeStarted)
            entries.append(written.entry)
            outcome.reports.append(report)

            if request.printsReport {
                log(report.summary)
            }
            for warning in report.warnings {
                log("spotforge: \(city.id): \(warning)")
            }
        }

        let index = try writer.writeIndex(updating: entries, generatedAt: now)
        outcome.indexPath = writer.indexURL.path
        log("spotforge: wrote \(index.cities.count) cities to \(request.outputDirectory)")
        return outcome
    }
}

extension BuildRequest {
    /// A cache directory is only useful when it exists; nothing else needs to
    /// know whether it did.
    public func prepareCacheDirectory() {
        guard let cacheDirectory else { return }
        try? FileManager.default.createDirectory(
            atPath: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}
