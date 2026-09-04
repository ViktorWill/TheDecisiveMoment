#if canImport(SwiftData)
import Foundation

/// Where an on-disk SwiftData store named `name` lives, in Application Support.
///
/// Three stores in this module — spots, gear, community — each declare their
/// own `Schema` and, until this existed, handed `ModelConfiguration(isStoredInMemoryOnly:)`
/// straight to `ModelContainer` with no explicit location. `ModelConfiguration`
/// with no `url:` resolves to the same fixed filename, `default.store`, no
/// matter which schema is passed — so all three silently shared one file.
/// Whichever container's `init` ran first won the schema that file actually
/// got; the other two then opened that same file expecting different tables
/// and failed the moment they queried, with an error naming the missing table
/// rather than anything that named the real cause.
enum ModelStoreLocation {
    static func url(named name: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("\(name).store")
    }
}
#endif
