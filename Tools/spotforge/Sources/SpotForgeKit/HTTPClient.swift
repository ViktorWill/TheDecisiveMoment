import Foundation
import TDMSpots

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP call, as the sources describe it.
public struct HTTPRequest: Sendable, Hashable {
    public var url: URL
    public var method: String
    public var body: Data?
    public var headers: [String: String]

    public init(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.body = body
        self.headers = headers
    }

    /// The disk-cache key: the whole request, not just the URL, because an
    /// Overpass query travels in the body.
    public var cacheKey: String {
        var material = "\(method) \(url.absoluteString)\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) where name.lowercased() != "user-agent" {
            material += "\(name): \(value)\n"
        }
        var data = Data(material.utf8)
        if let body { data.append(body) }
        return SHA256.hexDigest(data)
    }
}

public enum HTTPError: Error, CustomStringConvertible {
    case status(code: Int, url: URL, body: String)
    case transport(url: URL, underlying: String)
    case offline(url: URL)

    public var description: String {
        switch self {
        case let .status(code, url, body):
            "HTTP \(code) from \(url.absoluteString): \(body.prefix(200))"
        case let .transport(url, underlying):
            "could not reach \(url.absoluteString): \(underlying)"
        case .offline(let url):
            "\(url.absoluteString) is not in the fixture set and the network is disabled."
        }
    }
}

/// What actually moves the bytes. Tests substitute a transport that reads
/// recorded fixtures, which is how the suite stays offline.
public protocol Transport: Sendable {
    func send(_ request: HTTPRequest) async throws -> Data
}

/// `URLSession`, with the policies the volunteer-run services ask for applied
/// by the caller above rather than here.
public struct URLSessionTransport: Transport {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 240) {
        self.timeout = timeout
    }

    public func send(_ request: HTTPRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        // `dataTask` rather than the async `data(for:)`: the callback form is
        // the one corelibs-foundation has had for longest, and this tool has to
        // run on the Linux runner that regenerates the bundles.
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(
                        throwing: HTTPError.transport(url: request.url, underlying: error.localizedDescription)
                    )
                    return
                }
                let data = data ?? Data()
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    continuation.resume(
                        throwing: HTTPError.status(
                            code: http.statusCode,
                            url: request.url,
                            body: String(decoding: data, as: UTF8.self)
                        )
                    )
                    return
                }
                continuation.resume(returning: data)
            }
            task.resume()
        }
    }
}

/// A transport that only ever answers from a directory of recorded responses.
///
/// Used by the test suite and by `--fixtures`, so a full build can be exercised
/// end to end without a single packet leaving the machine.
public struct RecordedTransport: Transport {
    /// Cache key → response bytes.
    public var responses: [String: Data]

    public init(responses: [String: Data]) {
        self.responses = responses
    }

    /// Reads a directory of recordings. A file is matched by its whole stem or
    /// by the last dash-separated component of it, so a fixture can be named
    /// `commons-geosearch-{key}.json` and still be found by key — an opaque
    /// hash is a poor thing to review a diff of.
    public init(directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var responses: [String: Data] = [:]
        for name in names where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let stem = (name as NSString).deletingPathExtension
            responses[stem] = data
            if let key = stem.split(separator: "-").last.map(String.init) {
                responses[key] = data
            }
        }
        self.responses = responses
    }

    public func send(_ request: HTTPRequest) async throws -> Data {
        guard let data = responses[request.cacheKey] else { throw HTTPError.offline(url: request.url) }
        return data
    }
}

/// Rate limiting, caching and identification, in one place.
///
/// Overpass, WDQS and Commons are volunteer-run and their policies are explicit:
/// one request in flight at a time, a `User-Agent` that says who you are and how
/// to reach you, and a cache so a re-run of a failed build does not re-ask. The
/// actor is what enforces the first of those — every source shares one, so the
/// serialisation is across the whole build, not per source.
public actor RequestRunner {
    public static let defaultUserAgent =
        "spotforge/\(SpotForge.version) (The Decisive Moment; https://github.com/ViktorWill/TheDecisiveMoment; contact via GitHub issues)"

    private let transport: any Transport
    private let cacheDirectory: URL?
    private let userAgent: String
    private let minimumInterval: TimeInterval
    private var lastRequestFinished: Date?

    public private(set) var requestCount = 0
    public private(set) var cacheHitCount = 0

    public init(
        transport: any Transport,
        cacheDirectory: URL? = URL(fileURLWithPath: ".cache"),
        userAgent: String = RequestRunner.defaultUserAgent,
        minimumInterval: TimeInterval = 1
    ) {
        self.transport = transport
        self.cacheDirectory = cacheDirectory
        self.userAgent = userAgent
        self.minimumInterval = minimumInterval
    }

    public func send(_ request: HTTPRequest, cacheNamespace: String) async throws -> Data {
        let key = request.cacheKey
        if let cached = cachedResponse(namespace: cacheNamespace, key: key) {
            cacheHitCount += 1
            return cached
        }

        if let last = lastRequestFinished {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minimumInterval {
                try await Task.sleep(nanoseconds: UInt64((minimumInterval - elapsed) * 1_000_000_000))
            }
        }

        var identified = request
        identified.headers["User-Agent"] = userAgent
        defer { lastRequestFinished = Date() }
        let data = try await transport.send(identified)
        requestCount += 1
        store(data, namespace: cacheNamespace, key: key)
        return data
    }

    private func cacheURL(namespace: String, key: String) -> URL? {
        cacheDirectory?.appendingPathComponent(namespace).appendingPathComponent("\(key).json")
    }

    private func cachedResponse(namespace: String, key: String) -> Data? {
        guard let url = cacheURL(namespace: namespace, key: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func store(_ data: Data, namespace: String, key: String) {
        guard let url = cacheURL(namespace: namespace, key: key) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}
