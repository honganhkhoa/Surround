import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ASCCredentials: Sendable {
    public let keyId: String
    public let issuerId: String
    public let privateKeyPEM: String

    public init(keyId: String, issuerId: String, privateKeyPEM: String) {
        self.keyId = keyId
        self.issuerId = issuerId
        self.privateKeyPEM = privateKeyPEM
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ASCCredentials {
        func required(_ name: String) throws -> String {
            guard let value = environment[name], !value.isEmpty else {
                throw ReleaseToolError.validation("Missing required environment variable \(name)")
            }
            return value
        }
        let keyId = try required("ASC_KEY_ID")
        let issuerId = try required("ASC_ISSUER_ID")
        let keyPath = try required("ASC_PRIVATE_KEY_PATH")
        let pem: String
        do { pem = try String(contentsOfFile: keyPath, encoding: .utf8) }
        catch {
            throw ReleaseToolError.file("Could not read ASC_PRIVATE_KEY_PATH: \(error.localizedDescription)")
        }
        return ASCCredentials(keyId: keyId, issuerId: issuerId, privateKeyPEM: pem)
    }
}

public struct TransportResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) throws -> TransportResponse
}

/// Controls whether an individual App Store Connect request may be retried.
///
/// Use ``singleAttempt`` for mutations whose outcome must be reconciled before
/// another request is sent. The default preserves the client's existing retry
/// behavior for idempotent requests while continuing to keep POST single-shot.
public enum ASCRetryPolicy: Equatable, Sendable {
    case automatic
    case singleAttempt
}

/// Opt-in structured status reporting for callers that journal mutation intent.
/// The legacy request interface keeps its existing error behavior by default.
public struct ASCHTTPResponseError: Error, LocalizedError {
    public let statusCode: Int
    public let method: String
    public let path: String
    public var errorDescription: String? { "\(method) \(path) returned HTTP \(statusCode)" }
}

/// A known read response requested a cooldown longer than this invocation's
/// short retry budget. The caller preserves its checkpoint before resuming.
public struct ASCRateLimitCooldown: Error, LocalizedError {
    public let method: String
    public let path: String
    public let notBefore: Date
    public let serverSpecified: Bool
    public var errorDescription: String? {
        "\(method) \(path) requires rate-limit cooldown until \(ISO8601DateFormatter.releaseTool.string(from: notBefore)); "
            + (serverSpecified ? "server Retry-After was preserved" : "minimum backoff; server reset time is unknown")
            + ". No automatic retry was sent."
    }
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) throws -> TransportResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<TransportResponse, Error>?
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let response = response as? HTTPURLResponse else {
                result = .failure(ReleaseToolError.api("Server returned a non-HTTP response"))
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            result = .success(TransportResponse(
                data: data ?? Data(),
                statusCode: response.statusCode,
                headers: headers
            ))
        }
        task.resume()
        semaphore.wait()
        return try result!.get()
    }
}

public final class ASCAPIClient: @unchecked Sendable {
    public let baseURL: URL
    public let metrics: ASCRequestMetrics
    private let credentials: ASCCredentials
    private let transport: HTTPTransport
    private let maxRetries: Int
    private let now: () -> Date
    private let sleeper: (TimeInterval) -> Void
    private var cachedToken: (value: String, expires: Date)?
    private let lock = NSLock()
    private let pacingLock = NSLock()
    private var apiInterval: TimeInterval = 0
    private var lastAPIStart: Date?

    public init(
        credentials: ASCCredentials,
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!,
        transport: HTTPTransport = URLSessionTransport(),
        maxRetries: Int = 4,
        now: @escaping () -> Date = Date.init,
        sleeper: @escaping (TimeInterval) -> Void = Thread.sleep,
        metrics: ASCRequestMetrics? = nil
    ) {
        self.credentials = credentials
        self.baseURL = baseURL
        self.transport = transport
        self.maxRetries = maxRetries
        self.now = now
        self.sleeper = sleeper
        self.metrics = metrics ?? ASCRequestMetrics(now: now)
    }

    public func withPhase<T>(_ phase: ASCRequestPhase, _ operation: () throws -> T) rethrows -> T {
        try metrics.withPhase(phase, operation)
    }

    public func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: JSONValue? = nil,
        expectedStatus: Range<Int> = 200..<300,
        retryPolicy: ASCRetryPolicy = .automatic,
        reportHTTPStatus: Bool = false
    ) throws -> JSONValue? {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method.uppercased() == "GET" {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body.any, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try sendWithRetry(request, retryPolicy: retryPolicy, authenticatedAPI: true)
        guard expectedStatus.contains(response.statusCode) else {
            if reportHTTPStatus {
                throw ASCHTTPResponseError(statusCode: response.statusCode, method: method, path: url.path)
            }
            throw apiError(method: method, url: url, response: response)
        }
        guard !response.data.isEmpty else { return nil }
        do { return try JSONDecoder().decode(JSONValue.self, from: response.data) }
        catch {
            throw ReleaseToolError.api(
                "Could not decode \(method) \(url.path) response: \(error.localizedDescription)"
            )
        }
    }

    public func list(path: String, query: [URLQueryItem] = []) throws -> [JSONValue] {
        var nextPath: String? = path
        var nextQuery = query
        var resources: [JSONValue] = []
        while let current = nextPath {
            let response = try request(method: "GET", path: current, query: nextQuery)
            guard let object = response?.objectValue,
                  let data = object["data"]?.arrayValue else {
                throw ReleaseToolError.api("List response for \(current) has no data array")
            }
            resources.append(contentsOf: data)
            if let nextValue = object["links"]?["next"] {
                if case .null = nextValue {
                    nextPath = nil
                } else {
                    guard let link = nextValue.stringValue else {
                        throw ReleaseToolError.api(
                            "List response for \(current) has a non-string links.next"
                        )
                    }
                    // Validate before the next authenticated request is constructed so a
                    // malicious or malformed pagination link can never receive the JWT.
                    nextPath = try makeURL(path: link, query: []).absoluteString
                }
            } else {
                nextPath = nil
            }
            nextQuery = []
        }
        return resources
    }

    public func upload(operation: UploadOperation, fileData: Data, retryPolicy: ASCRetryPolicy = .automatic) throws {
        guard operation.offset >= 0, operation.length >= 0,
              operation.offset + operation.length <= fileData.count else {
            throw ReleaseToolError.validation("Upload operation has an invalid byte range")
        }
        guard let url = URL(string: operation.url) else {
            throw ReleaseToolError.validation("Upload operation URL is invalid")
        }
        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        request.httpBody = fileData.subdata(in: operation.offset..<(operation.offset + operation.length))
        for header in operation.requestHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let response = try sendWithRetry(request, retryPolicy: retryPolicy, category: .binaryUpload)
        guard (200..<300).contains(response.statusCode) else {
            throw apiError(method: operation.method, url: url, response: response)
        }
    }

    public func download(url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let response = try sendWithRetry(request, category: .imageDownload)
        guard (200..<300).contains(response.statusCode) else {
            throw apiError(method: "GET", url: url, response: response)
        }
        return response.data
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let initial: URL
        if let absolute = URL(string: path), absolute.scheme != nil {
            try requireSameOrigin(absolute)
            initial = absolute
        } else if path.hasPrefix("//"),
                  let networkPath = URL(string: path, relativeTo: baseURL)?.absoluteURL {
            try requireSameOrigin(networkPath)
            initial = networkPath
        } else {
            initial = baseURL.appendingPathComponent(
                path.hasPrefix("/") ? String(path.dropFirst()) : path
            )
        }
        guard var components = URLComponents(url: initial, resolvingAgainstBaseURL: false) else {
            throw ReleaseToolError.validation("Invalid API path: \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw ReleaseToolError.validation("Invalid API query for \(path)")
        }
        return url
    }

    private func requireSameOrigin(_ url: URL) throws {
        guard let requestedOrigin = origin(of: url),
              let apiOrigin = origin(of: baseURL),
              requestedOrigin == apiOrigin else {
            throw ReleaseToolError.api(
                "Refusing authenticated request to cross-origin URL \(url.absoluteString)"
            )
        }
    }

    private func origin(of url: URL) -> String? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), let scheme = components.scheme?.lowercased(),
           let host = components.host?.lowercased() else {
            return nil
        }
        let port = components.port ?? {
            switch scheme {
            case "http": return 80
            case "https": return 443
            default: return -1
            }
        }()
        return "\(scheme)://\(host):\(port)"
    }

    private func token() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let current = now()
        if let cachedToken, cachedToken.expires.timeIntervalSince(current) > 60 {
            return cachedToken.value
        }
        let header: [String: Any] = ["alg": "ES256", "kid": credentials.keyId, "typ": "JWT"]
        let expires = current.addingTimeInterval(19 * 60)
        let claims: [String: Any] = [
            "iss": credentials.issuerId,
            "iat": Int(current.timeIntervalSince1970),
            "exp": Int(expires.timeIntervalSince1970),
            "aud": "appstoreconnect-v1",
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsData = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let signingInput = "\(base64URL(headerData)).\(base64URL(claimsData))"
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM) }
        catch { throw ReleaseToolError.validation("ASC private key is not a valid P-256 PEM key") }
        let signature = try key.signature(for: Data(signingInput.utf8))
        let value = "\(signingInput).\(base64URL(signature.rawRepresentation))"
        cachedToken = (value, expires)
        return value
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sendWithRetry(
        _ request: URLRequest,
        retryPolicy: ASCRetryPolicy = .automatic,
        authenticatedAPI: Bool = false,
        category: ASCRequestCategory? = nil
    ) throws -> TransportResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        let retryLimit = retryPolicy == .singleAttempt ? 0 : maxRetries
        var lastError: Error?
        for attempt in 0...retryLimit {
            var outgoing = request
            let apiOrigin = origin(of: baseURL)
            let isAuthenticatedAPI = authenticatedAPI && request.value(forHTTPHeaderField: "Authorization") != nil
                && apiOrigin != nil && request.url.flatMap({ origin(of: $0) }) == apiOrigin
            let metricCategory = category ?? ((method == "GET" || method == "HEAD") ? .authenticatedRead : .authenticatedWrite)
            if isAuthenticatedAPI {
                paceAPI(category: metricCategory)
                // Pace before refreshing auth: a cooldown must not replay an
                // already expired JWT. CDN/upload requests never enter here.
                outgoing.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
            }
            let response: TransportResponse
            let metricAttempt = metrics.begin(category: metricCategory, retry: attempt > 0,
                                               sentBytes: outgoing.httpBody?.count ?? 0)
            do {
                response = try transport.send(outgoing)
            } catch {
                metrics.finish(metricAttempt, response: nil)
                lastError = error
                if method == "POST" || retryPolicy == .singleAttempt {
                    throw ReleaseToolError.api(
                        "\(method) \(request.url?.path ?? "<unknown>") failed with a network error "
                            + "and was not retried because its outcome is ambiguous. "
                            + "Inspect App Store Connect before resuming: \(error.localizedDescription)"
                    )
                }
                if attempt == retryLimit { break }
                try sleepBeforeRetry(attempt: attempt, headers: [:], request: request, rateLimited: false,
                                     category: metricCategory)
                continue
            }
            metrics.finish(metricAttempt, response: response)
            if isAuthenticatedAPI { observeRateLimit(response.headers) }
            if response.statusCode == 429 || response.statusCode >= 500 {
                if method == "POST" || retryPolicy == .singleAttempt {
                    let responseError = apiError(
                        method: method,
                        url: request.url ?? baseURL,
                        response: response
                    )
                    throw ReleaseToolError.api(
                        "\(responseError.description). The \(method) was not retried because "
                            + "its outcome is ambiguous; inspect App Store Connect before resuming."
                    )
                }
                if response.statusCode == 429 && attempt == retryLimit {
                    try sleepBeforeRetry(attempt: attempt, headers: response.headers, request: request,
                                         rateLimited: true, forcePause: true, category: metricCategory)
                }
                if attempt < retryLimit {
                    try sleepBeforeRetry(attempt: attempt, headers: response.headers, request: request,
                                         rateLimited: response.statusCode == 429, category: metricCategory)
                    continue
                }
            }
            return response
        }
        throw ReleaseToolError.api(
            "Network request failed after \(retryLimit + 1) attempts: \(lastError?.localizedDescription ?? "unknown error")"
        )
    }

    private func observeRateLimit(_ headers: [String: String]) {
        guard let value = headers.first(where: { $0.key.lowercased() == "x-rate-limit" })?.value else { return }
        var fields: [String: Int] = [:]
        for part in value.split(separator: ";") {
            let pair = part.split(separator: ":", maxSplits: 1)
            if pair.count == 2, let count = Int(pair[1].trimmingCharacters(in: .whitespaces)) {
                fields[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = count
            }
        }
        guard let limit = fields["user-hour-lim"], let remaining = fields["user-hour-rem"],
              limit > 0, remaining <= limit else { return }
        pacingLock.lock(); defer { pacingLock.unlock() }
        // Leave headroom for response accounting and other authorized readers.
        // Negative remaining values mean exhausted capacity. The header still
        // supplies the limit, not a reset deadline.
        apiInterval = 3600 / (Double(limit) * 0.8)
    }

    private func paceAPI(category: ASCRequestCategory) {
        pacingLock.lock()
        let current = now(), start = max(current, (lastAPIStart ?? current).addingTimeInterval(apiInterval))
        lastAPIStart = start
        pacingLock.unlock()
        let delay = max(0, start.timeIntervalSince(current))
        metrics.recordWait(delay, category: category, pacing: true)
        sleepInChunks(delay)
    }

    private func sleepInChunks(_ delay: TimeInterval) {
        var remaining = delay
        while remaining > 0 {
            let chunk = min(30, remaining); sleeper(chunk); remaining -= chunk
        }
    }

    private func sleepBeforeRetry(attempt: Int, headers: [String: String], request: URLRequest,
                                  rateLimited: Bool, forcePause: Bool = false,
                                  category: ASCRequestCategory) throws {
        let value = headers.first(where: { $0.key.lowercased() == "retry-after" })?.value
        var requested: TimeInterval?
        if let value {
            if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 {
                requested = seconds
            } else {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                if let date = formatter.date(from: value) { requested = max(0, date.timeIntervalSince(now())) }
            }
        }
        let delay = requested ?? (rateLimited ? 60 : min(pow(2, Double(attempt)), 8))
        if delay > 30 || forcePause {
            throw ASCRateLimitCooldown(method: request.httpMethod ?? "GET", path: request.url?.path ?? "<unknown>",
                notBefore: now().addingTimeInterval(delay), serverSpecified: requested != nil)
        }
        metrics.recordWait(delay, category: category, pacing: false)
        sleepInChunks(delay)
    }

    private func apiError(method: String, url: URL, response: TransportResponse) -> ReleaseToolError {
        var detail = String(data: response.data, encoding: .utf8) ?? ""
        if let value = try? JSONDecoder().decode(JSONValue.self, from: response.data),
           let errors = value["errors"]?.arrayValue {
            detail = errors.compactMap { item in
                let title = item["title"]?.stringValue
                let message = item["detail"]?.stringValue
                return [title, message].compactMap { $0 }.joined(separator: ": ")
            }.joined(separator: "; ")
        }
        if detail.count > 2_000 { detail = String(detail.prefix(2_000)) + "…" }
        return .api("\(method) \(url.path) returned HTTP \(response.statusCode): \(detail)")
    }
}

public struct UploadHeader: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
}

public struct UploadOperation: Codable, Equatable, Sendable {
    public let method: String
    public let url: String
    public let offset: Int
    public let length: Int
    public let requestHeaders: [UploadHeader]

    public static func parse(_ value: JSONValue) throws -> UploadOperation {
        guard let method = value["method"]?.stringValue,
              let url = value["url"]?.stringValue,
              let offset = value["offset"]?.intValue,
              let length = value["length"]?.intValue else {
            throw ReleaseToolError.api("Malformed screenshot upload operation")
        }
        let headers = value["requestHeaders"]?.arrayValue?.compactMap { header -> UploadHeader? in
            guard let name = header["name"]?.stringValue,
                  let value = header["value"]?.stringValue else { return nil }
            return UploadHeader(name: name, value: value)
        } ?? []
        return UploadOperation(
            method: method,
            url: url,
            offset: offset,
            length: length,
            requestHeaders: headers
        )
    }
}
