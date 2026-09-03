import Foundation
import TDMCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetching bytes, behind a protocol.
///
/// The download flow is tested against recorded responses on Linux, the same
/// arrangement `Tools/spotforge` uses for its four sources: a bundle refresh has
/// to be verifiable without a CDN, because what it does on a bad response is the
/// interesting half.
public protocol BundleTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Where the bundles are, `docs/DATA-BUNDLES.md` ("Layout on the CDN").
///
/// The schema version is in the path, so a future `v2` is a different root and
/// this build keeps reading `v1` — there is no forced update in a TestFlight app
/// and there should not be.
public struct BundleSource: Sendable, Hashable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public static let `default` = BundleSource(
        root: URL(string: "https://viktorwill.github.io/TheDecisiveMoment/bundles/v1/")!
    )

    public var indexURL: URL { root.appending(path: "index.json") }

    public func bundleURL(for entry: CityIndexEntry) -> URL {
        root.appending(path: entry.bundlePath)
    }
}

/// `URLSession` over the CDN.
///
/// The `User-Agent` is required rather than polite: Wikimedia's policy asks for
/// an identifying agent, and the same courtesy is owed to GitHub Pages.
public struct URLSessionBundleTransport: BundleTransport {
    public var userAgent: String
    public var session: URLSession

    public init(
        userAgent: String = "TheDecisiveMoment/0.1 (+https://github.com/ViktorWill/TheDecisiveMoment)",
        session: URLSession = .shared
    ) {
        self.userAgent = userAgent
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // The bundle is immutable for a given `bundleVersion`, and the index has
        // its own one-hour cache in the store, so the URL cache would only ever
        // hold a second, staler copy.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BundleTransportError.http(statusCode: http.statusCode, url: url)
        }
        return data
    }
}

public enum BundleTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    case http(statusCode: Int, url: URL)

    public var description: String {
        switch self {
        case let .http(statusCode, url):
            "HTTP \(statusCode) for \(url.lastPathComponent)."
        }
    }
}
