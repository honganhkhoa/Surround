//
//  OGSWebsocket.swift
//  Surround
//
//  Created by Anh Khoa Hong on 2023/4/6.
//

import Foundation
import Combine
import Alamofire

enum OGSWebsocketStatus: String {
    case disconnected
    case connecting
    case connected
    case reconnecting

    var localizedString: String {
        switch self {
        case .disconnected: return String(localized: "Disconnected", comment: "Connection status")
        case .connecting: return String(localized: "Connecting", comment: "Connection status")
        case .connected: return String(localized: "Connected", comment: "Connection status")
        case .reconnecting: return String(localized: "Reconnecting", comment: "Connection status")
        }
    }
}

/// Completion shape used by callback-bearing OGS WebSocket commands.
///
/// The first value is the decoded server payload. The second is an OGS error
/// dictionary or a locally generated `connection`, `encoding`, or `timeout`
/// error. `OGSWebsocket` completes each registered callback at most once.
typealias OGSWebsocketResultCallback = (Any?, [String: String]?) -> Void

/// The socket surface consumed by `OGSService`.
///
/// Deterministic service tests implement this protocol with an in-memory fake
/// so they can inject server events and inspect commands without opening a
/// network connection. Each live player should instead own a separate
/// `OGSWebsocket` instance so authentication and reconnection state cannot be
/// shared between accounts.
protocol OGSWebsocketProtocol: AnyObject {
    /// Receives OGS events and synthetic `surround/socket...` lifecycle events.
    var serverEventCallback: ((String, Any?) -> Void)? { get set }

    /// One-shot work to drain after the next transport connection opens.
    ///
    /// The transport may not yet be authenticated when these closures run,
    /// and terminal `close()` discards any closures that remain queued.
    var onConnectTasks: [() -> Void] { get set }

    /// Called whenever `status` changes.
    var onStatusChanged: (() -> Void)? { get set }

    /// Supplies the current identity at authentication time.
    ///
    /// This is a closure rather than a captured value so account changes are
    /// reflected by the next connection attempt.
    var authenticationConfigProvider: () -> OGSUIConfig? { get set }

    /// Whether authentication has been sent for the current open transport.
    /// This is local readiness state, not a server acknowledgement.
    var authenticated: Bool { get }

    /// Whether the underlying transport has reported that it is open.
    var opened: Bool { get }

    /// Current connection/reconnection state.
    var status: OGSWebsocketStatus { get }

    /// Estimated client/server clock difference in milliseconds.
    var drift: Double { get set }

    /// Estimated round-trip latency in milliseconds.
    var latency: Double { get set }

    /// Starts a fresh connection sequence.
    func connect()

    /// Permanently closes this socket instance and cancels pending work.
    func close()

    /// Starts reconnection only when there is no active connection attempt.
    func reconnectIfNeeded()

    /// Drops the current transport and enters the reconnection loop.
    func closeThenReconnect()

    /// Sends one OGS command, optionally correlating a server callback.
    func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?)
}

extension OGSWebsocketProtocol {
    func emit(command: String) {
        emit(command: command, data: [String: String](), resultCallback: nil)
    }

    func emit(command: String, data: Any) {
        emit(command: command, data: data, resultCallback: nil)
    }
}

/// A decoded frame from the OGS array-based WebSocket protocol.
enum OGSWebsocketFrame {
    /// A response shaped as `[callbackID, payload, error]`.
    case callback(id: Int, data: Any?, error: [String: String]?)

    /// A pushed event shaped as `[eventName, payload]`.
    case event(name: String, data: Any?)
}

/// Failures encountered while validating the JSON-compatible frame shape.
enum OGSWebsocketFrameCodecError: Error {
    case invalidJSONObject
    case invalidFrame
}

/// Encodes, decodes, and safely describes OGS WebSocket frames.
///
/// Keeping framing outside the transport lets tests verify callback IDs,
/// events, malformed input, and credential redaction without a network
/// connection. Use the redacted description methods for logs; `encode`
/// intentionally returns the real payload that is sent to OGS. Payloads must
/// be accepted by `JSONSerialization`, and incoming JSON `null` payloads are
/// exposed as `nil`.
///
/// Redaction is recursive but key-based. It protects known JWT, password,
/// token, CSRF, authorization, cookie, and session fields; it cannot guarantee
/// removal of secrets stored under unusual keys or as bare array values.
enum OGSWebsocketFrameCodec {
    /// Encodes a command as `[command, data]` or `[command, data, callbackID]`.
    static func encode(command: String, data: Any, callbackID: Int? = nil) throws -> String {
        var components: [Any] = [command, data]
        if let callbackID {
            components.append(callbackID)
        }

        guard JSONSerialization.isValidJSONObject(components) else {
            throw OGSWebsocketFrameCodecError.invalidJSONObject
        }
        let encoded = try JSONSerialization.data(withJSONObject: components)
        guard let message = String(data: encoded, encoding: .utf8) else {
            throw OGSWebsocketFrameCodecError.invalidJSONObject
        }
        return message
    }

    /// Decodes a callback or pushed-event frame received from OGS.
    static func decode(_ message: String) throws -> OGSWebsocketFrame {
        guard
            let messageData = message.data(using: .utf8),
            let components = try JSONSerialization.jsonObject(with: messageData) as? [Any],
            !components.isEmpty
        else {
            throw OGSWebsocketFrameCodecError.invalidFrame
        }

        let data = components.count > 1 ? optionalJSONValue(components[1]) : nil
        if let callbackID = components[0] as? Int {
            let error = components.count > 2 ? components[2] as? [String: String] : nil
            return .callback(id: callbackID, data: data, error: error)
        }
        if let eventName = components[0] as? String {
            return .event(name: eventName, data: data)
        }
        throw OGSWebsocketFrameCodecError.invalidFrame
    }

    /// Encodes a log-only representation with known credential fields removed.
    static func redactedDescription(command: String, data: Any, callbackID: Int?) -> String {
        (try? encode(command: command, data: redact(data), callbackID: callbackID))
            ?? "[\"\(command)\",\"<unprintable>\"]"
    }

    /// Redacts known credential fields in an already encoded JSON frame.
    static func redactedDescription(ofJSON message: String) -> String {
        guard
            let data = message.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(redact(object)),
            let redactedData = try? JSONSerialization.data(withJSONObject: redact(object)),
            let result = String(data: redactedData, encoding: .utf8)
        else {
            return "<unparseable websocket frame>"
        }
        return result
    }

    private static func optionalJSONValue(_ value: Any) -> Any? {
        value is NSNull ? nil : value
    }

    private static func redact(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else {
                return NSNull()
            }
            return redact(wrapped)
        }

        if let dictionary = value as? NSDictionary {
            var redactedDictionary: [String: Any] = [:]
            for (rawKey, rawValue) in dictionary {
                let key = String(describing: rawKey)
                redactedDictionary[key] = isSensitive(key: key) ? "<redacted>" : redact(rawValue)
            }
            return redactedDictionary
        }
        if let array = value as? NSArray {
            return array.map(redact)
        }
        return value
    }

    private static func isSensitive(key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized == "jwt"
            || normalized.contains("password")
            || normalized.contains("token")
            || normalized.contains("csrf")
            || normalized.contains("authorization")
            || normalized.contains("cookie")
            || normalized.contains("session")
    }
}

/// Receives lifecycle and message events from an `OGSWebsocketTransport`.
///
/// Test transports call these methods to deterministically simulate opening,
/// receiving a frame, closing, and failing.
protocol OGSWebsocketTransportDelegate: AnyObject {
    func websocketTransportDidOpen(_ transport: OGSWebsocketTransport)
    func websocketTransport(_ transport: OGSWebsocketTransport, didReceive message: String)
    func websocketTransport(_ transport: OGSWebsocketTransport, didCloseWith code: URLSessionWebSocketTask.CloseCode)
    func websocketTransport(_ transport: OGSWebsocketTransport, didFailWith error: Error)
}

/// Minimal I/O boundary used by the OGS socket protocol engine.
///
/// A transport handles only connection and string delivery. Authentication,
/// frame parsing, callback correlation, timeouts, and reconnection belong to
/// `OGSWebsocket`. Implementations should report activity through `delegate`
/// and complete every `send` attempt exactly once. `disconnect()` must be safe
/// to call repeatedly. A transport factory should return a fresh identity for
/// each attempt so the protocol engine can ignore stale delegate callbacks.
protocol OGSWebsocketTransport: AnyObject {
    var delegate: OGSWebsocketTransportDelegate? { get set }

    func connect(to url: URL)
    func send(_ message: String, completion: @escaping (Error?) -> Void)
    func disconnect()
}

/// Production transport backed by one `URLSessionWebSocketTask` at a time.
///
/// Its URL session is deliberately contained behind `OGSWebsocketTransport`,
/// allowing deterministic fake transports in unit tests. Calling `connect`
/// replaces any existing task; calling `disconnect` invalidates the session.
/// Delegate callbacks use a serial operation queue, text and UTF-8 data frames
/// are accepted, and `sessionFactory` is available as a lower-level test seam.
final class URLSessionOGSWebsocketTransport: NSObject, OGSWebsocketTransport, URLSessionWebSocketDelegate {
    weak var delegate: OGSWebsocketTransportDelegate?

    private let configuration: URLSessionConfiguration
    private let delegateQueue: OperationQueue
    private let sessionFactory: (URLSessionConfiguration, URLSessionDelegate, OperationQueue) -> URLSession
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    init(
        configuration: URLSessionConfiguration = .default,
        delegateQueue: OperationQueue? = nil,
        sessionFactory: @escaping (URLSessionConfiguration, URLSessionDelegate, OperationQueue) -> URLSession = {
            URLSession(configuration: $0, delegate: $1, delegateQueue: $2)
        }
    ) {
        self.configuration = configuration
        let queue = delegateQueue ?? OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.delegateQueue = queue
        self.sessionFactory = sessionFactory
        super.init()
    }

    func connect(to url: URL) {
        disconnect()
        let session = sessionFactory(configuration, self, delegateQueue)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
    }

    func send(_ message: String, completion: @escaping (Error?) -> Void) {
        guard let task else {
            completion(OGSWebsocketTransportError.notConnected)
            return
        }
        task.send(.string(message), completionHandler: completion)
    }

    func disconnect() {
        let activeTask = task
        task = nil
        activeTask?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard webSocketTask === task else { return }
        receive(from: webSocketTask)
        delegate?.websocketTransportDidOpen(self)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard webSocketTask === task else { return }
        delegate?.websocketTransport(self, didCloseWith: closeCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task, let error else { return }
        delegate?.websocketTransport(self, didFailWith: error)
    }

    private func receive(from task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task, task === self.task else { return }
            switch result {
            case .failure(let error):
                self.delegate?.websocketTransport(self, didFailWith: error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.delegate?.websocketTransport(self, didReceive: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.delegate?.websocketTransport(self, didReceive: text)
                    }
                @unknown default:
                    break
                }
                self.receive(from: task)
            }
        }
    }
}

/// Local transport failures propagated through command result callbacks.
enum OGSWebsocketTransportError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "The WebSocket is not connected"
        }
    }
}

/// Scheduling boundary for all socket state transitions and timers.
///
/// Production serializes work on the main queue. Deterministic tests inject a
/// scheduler that records delayed work and advances reconnect, watchdog, ping,
/// and callback-timeout tasks without waiting for wall-clock time. Custom
/// implementations must serialize state transitions and return cancellation
/// handles that actually prevent delayed or repeating work from firing.
protocol OGSWebsocketScheduling: AnyObject {
    /// Enqueues an immediate state transition.
    func async(_ block: @escaping () -> Void)

    /// Schedules cancellable one-shot work.
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable

    /// Schedules cancellable repeating work.
    func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

/// Main-queue scheduler used by production sockets.
final class OGSMainQueueWebsocketScheduler: OGSWebsocketScheduling {
    static let shared = OGSMainQueueWebsocketScheduler()

    private init() {}

    func async(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let work = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return AnyCancellable { work.cancel() }
    }

    func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in block() }
    }
}

/// Loads an anonymous UI configuration from the supplied OGS HTTP origin.
///
/// Tests inject this closure to avoid REST traffic and to control success or
/// failure. It is invoked only when the authentication provider returns nil
/// and must call its completion exactly once. The production default requests
/// `/api/v1/ui/config` through an ephemeral session.
typealias OGSAnonymousConfigLoader = (URL, @escaping (Result<OGSUIConfig, Error>) -> Void) -> Void

/// OGS WebSocket protocol engine with injectable I/O and time.
///
/// This class owns authentication, frame dispatch, callback correlation,
/// redacted logging, ping timing, and capped exponential reconnect delays.
/// The transport and scheduler abstractions keep those behaviors deterministic
/// in unit tests, while the default initializer retains production behavior.
class OGSWebsocket: NSObject, OGSWebsocketProtocol, OGSWebsocketTransportDelegate {
    private let rootURL: URL
    private let websocketURL: URL
    private let transportFactory: () -> OGSWebsocketTransport
    private let scheduler: OGSWebsocketScheduling
    private let anonymousConfigLoader: OGSAnonymousConfigLoader
    private let callbackTimeout: TimeInterval
    private let logger: (String) -> Void

    private var transport: OGSWebsocketTransport?
    private var latestCallbackID = 0
    private var callbackByID: [Int: OGSWebsocketResultCallback] = [:]
    private var callbackTimeoutByID: [Int: Cancellable] = [:]

    var serverEventCallback: ((String, Any?) -> Void)?
    var onConnectTasks: [() -> Void] = []
    var onStatusChanged: (() -> Void)?
    var authenticationConfigProvider: () -> OGSUIConfig?
    var anonymousUIConfig: OGSUIConfig?

    private(set) var authenticated = false
    private(set) var opened = false
    private(set) var status = OGSWebsocketStatus.connecting {
        didSet { onStatusChanged?() }
    }

    // MARK: - Reconnection state

    private var isReconnecting = false
    private var reconnectAttempt = 0
    private var connectWatchdog: Cancellable?
    private var pendingReconnect: Cancellable?
    private let connectTimeout: TimeInterval
    private let maxReconnectDelay: TimeInterval
    private var anonymousConfigRequestInFlight = false
    private var pingCancellable: Cancellable?
    private var isClosed = false

    var drift = 0.0
    var latency = 0.0

    override convenience init() {
        self.init(rootURL: URL(string: OGSService.ogsRoot)!)
    }

    /// Creates a socket protocol engine.
    ///
    /// - Parameters:
    ///   - rootURL: OGS HTTP origin used when anonymous configuration is needed.
    ///   - websocketURL: Socket endpoint. When omitted, it is derived from
    ///     `rootURL` by mapping HTTP to WS and HTTPS to WSS.
    ///   - authenticationConfigProvider: Returns the identity to authenticate
    ///     on each connection. `OGSService` replaces this with its scoped
    ///     configuration provider.
    ///   - transportFactory: Creates a new transport for every connection
    ///     attempt. Tests use this to retain and drive fake transports.
    ///   - scheduler: Serializes socket state and owns all delayed/repeating
    ///     work. Tests use a manually advanced scheduler.
    ///   - anonymousConfigLoader: Fetches anonymous credentials when no logged-in
    ///     configuration exists. Inject a stub to keep unit tests offline.
    ///   - connectTimeout: Time before an unopened transport is treated as failed.
    ///   - maxReconnectDelay: Upper bound for exponential reconnect backoff.
    ///   - callbackTimeout: Time before an unanswered callback fails locally.
    ///   - logger: Diagnostic sink. Frame descriptions passed by this class are
    ///     credential-redacted; custom loggers must not add raw payload capture.
    ///
    /// Initialization does not open the transport. Call `connect()` directly,
    /// or let an owning `OGSService` connect it during service initialization.
    init(
        rootURL: URL,
        websocketURL: URL? = nil,
        authenticationConfigProvider: @escaping () -> OGSUIConfig? = { userDefaults[.ogsUIConfig] },
        transportFactory: @escaping () -> OGSWebsocketTransport = { URLSessionOGSWebsocketTransport() },
        scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared,
        anonymousConfigLoader: OGSAnonymousConfigLoader? = nil,
        connectTimeout: TimeInterval = 15,
        maxReconnectDelay: TimeInterval = 30,
        callbackTimeout: TimeInterval = 30,
        logger: @escaping (String) -> Void = { print($0) }
    ) {
        self.rootURL = rootURL
        self.websocketURL = websocketURL ?? Self.websocketURL(from: rootURL)
        self.authenticationConfigProvider = authenticationConfigProvider
        self.transportFactory = transportFactory
        self.scheduler = scheduler
        self.anonymousConfigLoader = anonymousConfigLoader ?? Self.makeAnonymousConfigLoader()
        self.connectTimeout = connectTimeout
        self.maxReconnectDelay = maxReconnectDelay
        self.callbackTimeout = callbackTimeout
        self.logger = logger
        super.init()
    }

    /// Resets reconnect backoff and starts a fresh connection attempt.
    func connect() {
        scheduler.async {
            guard !self.isClosed else { return }
            self.status = .connecting
            self.isReconnecting = false
            self.reconnectAttempt = 0
            self.startNewConnection()
        }
    }

    /// Permanently shuts down this socket instance. Unlike
    /// `closeThenReconnect()`, no connection attempt is scheduled afterward.
    /// A closed instance intentionally cannot be restarted; create a new
    /// instance for a new isolated session.
    func close() {
        scheduler.async {
            guard !self.isClosed else { return }
            self.isClosed = true
            self.isReconnecting = false

            self.connectWatchdog?.cancel()
            self.connectWatchdog = nil
            self.pendingReconnect?.cancel()
            self.pendingReconnect = nil
            self.pingCancellable?.cancel()
            self.pingCancellable = nil

            self.transport?.delegate = nil
            self.transport?.disconnect()
            self.transport = nil
            self.opened = false
            self.authenticated = false
            self.anonymousConfigRequestInFlight = false
            self.onConnectTasks = []
            self.failPendingCallbacks(reason: "WebSocket was closed")
            self.status = .disconnected
        }
    }

    /// Enters recovery only when no socket or connection attempt is active.
    func reconnectIfNeeded() {
        scheduler.async {
            guard !self.isClosed else { return }
            guard !self.opened, !self.isReconnecting, self.status != .connecting else {
                return
            }
            self.enterReconnecting()
        }
    }

    func authenticateWebsocket() {
        guard !isClosed else { return }
        let config = authenticationConfigProvider() ?? anonymousUIConfig
        if let config {
            emit(command: "authenticate", data: ["jwt": config.userJwt])
            if config.user.anonymous == false {
                emit(command: "automatch/list")
            }
            scheduler.async {
                self.authenticated = true
                self.serverEventCallback?("surround/socketAuthenticated", nil)
            }
            return
        }

        guard !anonymousConfigRequestInFlight else { return }
        anonymousConfigRequestInFlight = true
        anonymousConfigLoader(rootURL) { [weak self] result in
            guard let self else { return }
            self.scheduler.async {
                guard !self.isClosed else { return }
                self.anonymousConfigRequestInFlight = false
                switch result {
                case .success(let config):
                    self.anonymousUIConfig = config
                    self.authenticateWebsocket()
                case .failure(let error):
                    self.log("Error getting anonymous config: \(error)")
                }
            }
        }
    }

    func emit(
        command: String,
        data: Any = [String: String](),
        resultCallback: OGSWebsocketResultCallback? = nil
    ) {
        scheduler.async {
            guard !self.isClosed else {
                resultCallback?(nil, ["connection": "WebSocket was closed"])
                return
            }
            var callbackID: Int?
            if let resultCallback {
                self.latestCallbackID += 1
                callbackID = self.latestCallbackID
                self.callbackByID[self.latestCallbackID] = resultCallback
                self.scheduleCallbackTimeout(id: self.latestCallbackID)
            }

            let message: String
            do {
                message = try OGSWebsocketFrameCodec.encode(
                    command: command,
                    data: data,
                    callbackID: callbackID
                )
            } catch {
                self.log("Cannot encode command \(command): \(error)")
                if let callbackID {
                    self.completeCallback(
                        id: callbackID,
                        data: nil,
                        error: ["encoding": error.localizedDescription]
                    )
                }
                return
            }

            self.log(
                "Sending \(OGSWebsocketFrameCodec.redactedDescription(command: command, data: data, callbackID: callbackID))"
            )

            guard let transport = self.transport else {
                if let callbackID {
                    self.completeCallback(
                        id: callbackID,
                        data: nil,
                        error: ["connection": OGSWebsocketTransportError.notConnected.localizedDescription]
                    )
                }
                return
            }
            transport.send(message) { [weak self, weak transport] error in
                guard let self, let transport, let error else { return }
                self.log("Sending failed: \(error)")
                self.scheduler.async {
                    if let callbackID {
                        self.completeCallback(
                            id: callbackID,
                            data: nil,
                            error: ["connection": error.localizedDescription]
                        )
                    }
                }
                self.handleConnectionFailure(for: transport)
            }
        }
    }

    /// Tears down the current transport and schedules exponential reconnection.
    ///
    /// Pending callbacks fail immediately, and the first retry is scheduled
    /// after one second. Use terminal `close()` during test teardown instead.
    func closeThenReconnect() {
        scheduler.async {
            guard !self.isClosed else { return }
            self.enterReconnecting()
        }
    }

    // MARK: - OGSWebsocketTransportDelegate

    func websocketTransportDidOpen(_ transport: OGSWebsocketTransport) {
        scheduler.async {
            guard transport === self.transport else { return }

            self.connectWatchdog?.cancel()
            self.connectWatchdog = nil
            self.pendingReconnect?.cancel()
            self.pendingReconnect = nil
            self.isReconnecting = false
            self.reconnectAttempt = 0

            self.status = .connected
            self.opened = true
            self.log("Opened")

            self.pingCancellable = self.scheduler.scheduleRepeating(every: 10) {
                self.emit(
                    command: "net/ping",
                    data: [
                        "client": Date().timeIntervalSince1970 * 1000,
                        "drift": self.drift,
                        "latency": self.latency
                    ]
                )
            }
            self.authenticateWebsocket()

            let tasks = self.onConnectTasks
            self.onConnectTasks = []
            tasks.forEach { $0() }
            self.serverEventCallback?("surround/socketOpened", nil)
        }
    }

    func websocketTransport(_ transport: OGSWebsocketTransport, didReceive message: String) {
        guard transport === self.transport else { return }
        log("Received string: \(OGSWebsocketFrameCodec.redactedDescription(ofJSON: message))")
        processServerMessage(message)
    }

    func websocketTransport(
        _ transport: OGSWebsocketTransport,
        didCloseWith code: URLSessionWebSocketTask.CloseCode
    ) {
        log("Closed with code \(code.rawValue)")
        handleConnectionFailure(for: transport)
    }

    func websocketTransport(_ transport: OGSWebsocketTransport, didFailWith error: Error) {
        log("Received error: \(error)")
        handleConnectionFailure(for: transport)
    }

    // MARK: - Message dispatch

    func processServerMessage(_ message: String) {
        let frame: OGSWebsocketFrame
        do {
            frame = try OGSWebsocketFrameCodec.decode(message)
        } catch {
            log("Ignoring malformed server message: \(error)")
            return
        }

        scheduler.async {
            switch frame {
            case .callback(let id, let data, let error):
                self.completeCallback(id: id, data: data, error: error)
            case .event(let name, let data):
                self.serverEventCallback?(name, data)
            }
        }
    }

    private func scheduleCallbackTimeout(id: Int) {
        callbackTimeoutByID[id] = scheduler.schedule(after: callbackTimeout) { [weak self] in
            guard let self, self.callbackByID[id] != nil else { return }
            self.completeCallback(
                id: id,
                data: nil,
                error: ["timeout": "No WebSocket response received within \(self.callbackTimeout) seconds"]
            )
        }
    }

    private func completeCallback(id: Int, data: Any?, error: [String: String]?) {
        callbackTimeoutByID.removeValue(forKey: id)?.cancel()
        callbackByID.removeValue(forKey: id)?(data, error)
    }

    // MARK: - Reconnection engine

    private func enterReconnecting() {
        guard !isClosed else { return }
        let wasReconnecting = isReconnecting

        connectWatchdog?.cancel()
        connectWatchdog = nil
        pingCancellable?.cancel()
        pingCancellable = nil
        opened = false
        authenticated = false
        transport?.delegate = nil
        transport?.disconnect()
        transport = nil
        failPendingCallbacks(reason: "WebSocket connection closed")

        status = .reconnecting

        if !wasReconnecting {
            isReconnecting = true
            reconnectAttempt = 0
            log("Reconnecting...")
            serverEventCallback?("surround/socketClosed", nil)
        }

        scheduleNextConnectionAttempt()
    }

    private func handleConnectionFailure(for transport: OGSWebsocketTransport) {
        scheduler.async {
            guard transport === self.transport else { return }
            self.enterReconnecting()
        }
    }

    private func scheduleNextConnectionAttempt() {
        pendingReconnect?.cancel()

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1
        log("Next connection attempt in \(Int(delay))s (attempt \(reconnectAttempt))")

        pendingReconnect = scheduler.schedule(after: delay) { [weak self] in
            guard let self, !self.isClosed, self.isReconnecting else { return }
            self.startNewConnection()
        }
    }

    private func startNewConnection() {
        guard !isClosed else { return }
        connectWatchdog?.cancel()
        connectWatchdog = nil
        transport?.delegate = nil
        transport?.disconnect()

        opened = false
        authenticated = false
        let transport = transportFactory()
        self.transport = transport
        transport.delegate = self
        transport.connect(to: websocketURL)
        log("Opening connection...")

        connectWatchdog = scheduler.schedule(after: connectTimeout) { [weak self, weak transport] in
            guard
                let self,
                let transport,
                transport === self.transport,
                !self.opened
            else {
                return
            }
            self.log("Connection attempt timed out")
            self.enterReconnecting()
        }
    }

    private func failPendingCallbacks(reason: String) {
        let callbackIDs = Array(callbackByID.keys)
        for callbackID in callbackIDs {
            completeCallback(id: callbackID, data: nil, error: ["connection": reason])
        }
    }

    private func log(_ message: String) {
        logger("[websocket] \(message)")
    }

    private static func websocketURL(from rootURL: URL) -> URL {
        var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false)!
        components.scheme = rootURL.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    private static func makeAnonymousConfigLoader() -> OGSAnonymousConfigLoader {
        let session = Session(configuration: .ephemeral)
        return { rootURL, completion in
            let configURL = rootURL.appendingPathComponent("api/v1/ui/config")
            session.request(configURL).validate().responseData { response in
                switch response.result {
                case .success(let data):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    do {
                        completion(.success(try decoder.decode(OGSUIConfig.self, from: data)))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
