import Foundation
import Synchronization
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
    /// `URLRequest.timeoutInterval`: resets on every byte received, so a
    /// server that dribbles data slowly never trips it.
    public var timeout: TimeInterval
    /// A wall-clock ceiling on top of `timeout`, because inactivity alone is
    /// not a deadline: a request that stays "active" — a byte every few
    /// seconds — can otherwise run forever and stall the whole build.
    public var deadline: TimeInterval

    public init(timeout: TimeInterval = 240, deadline: TimeInterval = 300) {
        self.timeout = timeout
        self.deadline = deadline
    }

    public func send(_ request: HTTPRequest) async throws -> Data {
        var mutableRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        mutableRequest.httpMethod = request.method
        mutableRequest.httpBody = request.body
        for (name, value) in request.headers {
            mutableRequest.setValue(value, forHTTPHeaderField: name)
        }
        let urlRequest = mutableRequest

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await Self.perform(urlRequest, url: request.url) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                throw HTTPError.transport(
                    url: request.url,
                    underlying: "exceeded the \(Int(deadline))s request deadline"
                )
            }
            defer { group.cancelAll() }
            // Whichever finishes first — the response, or the deadline —
            // decides the outcome; `cancelAll` above stops the loser, which
            // for the network task also cancels the in-flight `URLSessionTask`.
            guard let result = try await group.next() else {
                throw HTTPError.transport(url: request.url, underlying: "no result")
            }
            return result
        }
    }

    /// `dataTask` rather than the async `data(for:)`: the callback form is
    /// the one corelibs-foundation has had for longest, and this tool has to
    /// run on the Linux runner that regenerates the bundles.
    private static func perform(_ urlRequest: URLRequest, url: URL) async throws -> Data {
        let box = CancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(
                            throwing: HTTPError.transport(url: url, underlying: error.localizedDescription)
                        )
                        return
                    }
                    let data = data ?? Data()
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        continuation.resume(
                            throwing: HTTPError.status(
                                code: http.statusCode,
                                url: url,
                                body: String(decoding: data, as: UTF8.self)
                            )
                        )
                        return
                    }
                    continuation.resume(returning: data)
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Holds the in-flight `URLSessionTask` just long enough for the deadline
/// timer to be able to cancel it from another task. `Mutex` rather than
/// `@unchecked Sendable`: the box crosses into `onCancel`, which can run on a
/// different thread than the one that created the task.
private final class CancellableTaskBox: Sendable {
    private let task = Mutex<URLSessionTask?>(nil)

    func set(_ value: URLSessionTask) {
        task.withLock { $0 = value }
    }

    func cancel() {
        task.withLock { $0?.cancel() }
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
/// Overpass and WDQS are volunteer-run and their policies are explicit: one
/// request in flight at a time. Commons' `geosearch` is a different service
/// with no such restriction, so it gets its own, more permissive policy —
/// `docs/SPOTFORGE.md` §9 and PR #16. Every namespace still gets a
/// `User-Agent` that says who you are and how to reach you, and a cache so a
/// re-run of a failed build does not re-ask.
public actor RequestRunner {
    public static let defaultUserAgent =
        "spotforge/\(SpotForge.version) (The Decisive Moment; https://github.com/ViktorWill/TheDecisiveMoment; contact via GitHub issues)"

    /// How polite to be with one namespace: at most `concurrency` requests in
    /// flight at once, each namespace-wide gap between finishes at least
    /// `minimumInterval`.
    public struct HostPolicy: Sendable {
        public var concurrency: Int
        public var minimumInterval: TimeInterval

        public init(concurrency: Int = 1, minimumInterval: TimeInterval = 1) {
            self.concurrency = max(1, concurrency)
            self.minimumInterval = minimumInterval
        }
    }

    /// A small overlap for Commons — a different service from Overpass, with
    /// no "one at a time" policy — cuts the sweep by most of its length
    /// without hammering anyone. Overpass and WDQS keep the serial default.
    public static let politeCommonsPolicy = HostPolicy(concurrency: 3, minimumInterval: 1)

    /// Per-namespace concurrency slots and the last time each namespace
    /// finished a request, for the interval check below.
    private final class NamespaceState {
        var activeCount = 0
        var lastFinished: Date?
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let transport: any Transport
    private let cacheDirectory: URL?
    private let userAgent: String
    private let defaultPolicy: HostPolicy
    private let namespacePolicies: [String: HostPolicy]
    private var namespaceStates: [String: NamespaceState] = [:]

    public private(set) var requestCount = 0
    public private(set) var cacheHitCount = 0

    public init(
        transport: any Transport,
        cacheDirectory: URL? = URL(fileURLWithPath: ".cache"),
        userAgent: String = RequestRunner.defaultUserAgent,
        minimumInterval: TimeInterval = 1,
        namespacePolicies: [String: HostPolicy] = [:]
    ) {
        self.transport = transport
        self.cacheDirectory = cacheDirectory
        self.userAgent = userAgent
        self.defaultPolicy = HostPolicy(concurrency: 1, minimumInterval: minimumInterval)
        self.namespacePolicies = namespacePolicies
    }

    private func policy(for namespace: String) -> HostPolicy {
        namespacePolicies[namespace] ?? defaultPolicy
    }

    public func send(_ request: HTTPRequest, cacheNamespace: String) async throws -> Data {
        let key = request.cacheKey
        if let cached = cachedResponse(namespace: cacheNamespace, key: key) {
            cacheHitCount += 1
            return cached
        }

        let policy = policy(for: cacheNamespace)
        await acquireSlot(namespace: cacheNamespace, concurrency: policy.concurrency)
        do {
            if let last = namespaceStates[cacheNamespace]?.lastFinished {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < policy.minimumInterval {
                    try await Task.sleep(nanoseconds: UInt64((policy.minimumInterval - elapsed) * 1_000_000_000))
                }
            }

            var identified = request
            identified.headers["User-Agent"] = userAgent
            let data = try await transport.send(identified)
            requestCount += 1
            store(data, namespace: cacheNamespace, key: key)
            finishSlot(namespace: cacheNamespace)
            return data
        } catch {
            finishSlot(namespace: cacheNamespace)
            throw error
        }
    }

    /// Blocks until fewer than `concurrency` requests are already active for
    /// this namespace. A namespace with `concurrency: 1` is therefore exactly
    /// as serial as the runner used to be for everyone.
    private func acquireSlot(namespace: String, concurrency: Int) async {
        let state = namespaceStates[namespace] ?? {
            let state = NamespaceState()
            namespaceStates[namespace] = state
            return state
        }()
        if state.activeCount < concurrency {
            state.activeCount += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.waiters.append(continuation)
        }
    }

    /// Releases this namespace's slot, handing it straight to the oldest
    /// waiter if there is one, and records the finish time the interval check
    /// above reads.
    private func finishSlot(namespace: String) {
        guard let state = namespaceStates[namespace] else { return }
        state.lastFinished = Date()
        if !state.waiters.isEmpty {
            state.waiters.removeFirst().resume()
        } else {
            state.activeCount -= 1
        }
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
