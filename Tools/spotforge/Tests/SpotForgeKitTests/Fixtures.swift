import Foundation
import SpotForgeKit

/// Every test reads from the recorded responses under `Tests/Fixtures`. Nothing
/// here opens a socket: a build tool whose tests need the network is a build
/// tool that cannot be tested at all once a volunteer service is busy.
enum Fixtures {
    static let directory: URL = {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures were not copied into the test bundle")
        }
        return url
    }()

    static var citiesPath: String { directory.appendingPathComponent("cities.yml").path }
    static var curatedDirectory: String { directory.appendingPathComponent("curated").path }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    static func data(matching label: String) throws -> Data {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard let match = names.first(where: { $0.hasPrefix("\(label)-") && $0.hasSuffix(".json") }) else {
            fatalError("No fixture recorded for \(label)")
        }
        return try Data(contentsOf: directory.appendingPathComponent(match))
    }

    static func transport() throws -> RecordedTransport {
        try RecordedTransport(directory: directory)
    }

    /// No cache and no pacing delay: the recorded transport is the cache, and a
    /// one-second courtesy pause between fixtures would only slow the suite.
    static func runner() throws -> RequestRunner {
        RequestRunner(transport: try transport(), cacheDirectory: nil, minimumInterval: 0)
    }

    static let bbox = try! CityCatalog.load(contentsOf: citiesPath).city(withId: "us-nyc").bbox

    /// The repository root, found by walking up from this file. Used by the two
    /// tests that assert on the real `data/` files rather than the fixtures.
    static let repositoryRoot: URL = {
        // …/Tools/spotforge/Tests/SpotForgeKitTests/Fixtures.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotforge-tests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
