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
    private let credentials: ASCCredentials
    private let transport: HTTPTransport
    private let maxRetries: Int
    private let now: () -> Date
    private var cachedToken: (value: String, expires: Date)?
    private let lock = NSLock()

    public init(
        credentials: ASCCredentials,
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!,
        transport: HTTPTransport = URLSessionTransport(),
        maxRetries: Int = 4,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.baseURL = baseURL
        self.transport = transport
        self.maxRetries = maxRetries
        self.now = now
    }

    public func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: JSONValue? = nil,
        expectedStatus: Range<Int> = 200..<300
    ) throws -> JSONValue? {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body.any, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try sendWithRetry(request)
        guard expectedStatus.contains(response.statusCode) else {
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

    public func upload(operation: UploadOperation, fileData: Data) throws {
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
        let response = try sendWithRetry(request)
        guard (200..<300).contains(response.statusCode) else {
            throw apiError(method: operation.method, url: url, response: response)
        }
    }

    public func download(url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response = try sendWithRetry(request)
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

    private func sendWithRetry(_ request: URLRequest) throws -> TransportResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        var lastError: Error?
        for attempt in 0...maxRetries {
            let response: TransportResponse
            do {
                response = try transport.send(request)
            } catch {
                lastError = error
                if method == "POST" {
                    throw ReleaseToolError.api(
                        "POST \(request.url?.path ?? "<unknown>") failed with a network error "
                            + "and was not retried because its outcome is ambiguous. "
                            + "Inspect App Store Connect before resuming: \(error.localizedDescription)"
                    )
                }
                if attempt == maxRetries { break }
                sleepBeforeRetry(attempt: attempt, headers: [:])
                continue
            }
            if response.statusCode == 429 || response.statusCode >= 500 {
                if method == "POST" {
                    let responseError = apiError(
                        method: method,
                        url: request.url ?? baseURL,
                        response: response
                    )
                    throw ReleaseToolError.api(
                        "\(responseError.description). The POST was not retried because "
                            + "its outcome is ambiguous; inspect App Store Connect before resuming."
                    )
                }
                if attempt < maxRetries {
                    sleepBeforeRetry(attempt: attempt, headers: response.headers)
                    continue
                }
            }
            return response
        }
        throw ReleaseToolError.api(
            "Network request failed after \(maxRetries + 1) attempts: \(lastError?.localizedDescription ?? "unknown error")"
        )
    }

    private func sleepBeforeRetry(attempt: Int, headers: [String: String]) {
        let delay = headers["retry-after"].flatMap(TimeInterval.init)
            ?? min(pow(2, Double(attempt)), 8)
        Thread.sleep(forTimeInterval: max(0, min(delay, 30)))
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
