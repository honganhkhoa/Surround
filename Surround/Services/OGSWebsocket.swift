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

class OGSWebsocket: NSObject, URLSessionWebSocketDelegate {
    private var websocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var websocketDelegateQueue: OperationQueue
    private var websocketURL: URL

    private var latestCallbackId = 0
    private var callbackById: [Int: (Any?, [String: String]?) -> ()] = [:]
    
    public var serverEventCallback: ((String, Any?) -> ())?
    public var onConnectTasks: [() -> ()] = []
    public var onStatusChanged: (() -> ())?
    
    public var anonymousUIConfig: OGSUIConfig?

    private var pingCancellable: AnyCancellable?
    private(set) public var authenticated = false
    private(set) public var opened = false
    private(set) public var status = OGSWebsocketStatus.connecting {
        didSet {
            if let callback = onStatusChanged {
                callback()
            }
        }
    }

    // MARK: - Reconnection state
    //
    // All of the reconnection bookkeeping below is only ever touched on the main
    // queue. Delegate callbacks arrive on `websocketDelegateQueue`, so every
    // handler hops back onto main before reading or mutating this state.

    /// True while we are actively trying to (re)establish a connection. While
    /// this is set, failed attempts schedule the next attempt instead of
    /// dead-ending, so the socket can never get permanently stuck.
    private var isReconnecting = false
    /// Number of connection attempts made in the current reconnect cycle, used
    /// to compute the backoff delay.
    private var reconnectAttempt = 0
    /// Fires if a connection attempt neither opens nor errors within the
    /// timeout (e.g. the network stack isn't ready right after foregrounding).
    private var connectWatchdog: DispatchWorkItem?
    /// The next scheduled connection attempt, kept so we never schedule two.
    private var pendingReconnect: DispatchWorkItem?
    /// How long a single attempt may spend trying to open before we give up on
    /// it and retry.
    private let connectTimeout: TimeInterval = 15
    /// Upper bound on the exponential backoff between attempts.
    private let maxReconnectDelay: TimeInterval = 30

    private lazy var jsonEncoder = JSONEncoder()

    public var drift = 0.0
    public var latency = 0.0

    override init() {
        var urlComponents = URLComponents(url: URL(string: OGSService.ogsRoot)!, resolvingAgainstBaseURL: true)
        urlComponents?.scheme = "wss"
        websocketURL = urlComponents!.url!

        websocketDelegateQueue = OperationQueue()
        websocketDelegateQueue.maxConcurrentOperationCount = 1

        super.init()
    }
    
    public func connect() {
        DispatchQueue.main.async {
            self.status = .connecting
            self.isReconnecting = false
            self.reconnectAttempt = 0
            self.startNewConnection()
        }
    }

    /// Kicks a reconnect if the socket is neither open nor already trying to
    /// connect. Used as a safety net from `ensureConnect` so a dead socket is
    /// revived instead of silently queuing callbacks forever.
    public func reconnectIfNeeded() {
        DispatchQueue.main.async {
            guard !self.opened, !self.isReconnecting, self.status != .connecting else {
                return
            }
            self.enterReconnecting()
        }
    }
    
    var anonymousSession: Session? = nil
    public func authenticateWebsocket() {
        let config = userDefaults[.ogsUIConfig] ?? self.anonymousUIConfig
        if let config {
            emit(command: "authenticate", data: ["jwt": config.userJwt])
            if config.user.anonymous == false {
                emit(command: "automatch/list")
            }
            DispatchQueue.main.async {
                self.authenticated = true
                if let callback = self.serverEventCallback {
                    callback("surround/socketAuthenticated", nil)
                }
            }
        } else {
            if anonymousSession == nil {
                self.anonymousSession = Session(configuration: .ephemeral)
                self.anonymousSession?.request("\(OGSService.ogsRoot)/api/v1/ui/config").validate().responseData { response in
                    switch response.result {
                    case .success:
                        if let result = response.value {
                            let jsonDecoder = JSONDecoder()
                            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
                            if let config = try? jsonDecoder.decode(OGSUIConfig.self, from: result) {
                                self.anonymousUIConfig = config
                                self.emit(command: "authenticate", data: ["jwt": config.userJwt])
                                DispatchQueue.main.async {
                                    self.authenticated = true
                                    if let callback = self.serverEventCallback {
                                        callback("surround/socketAuthenticated", nil)
                                    }
                                }
                            }
                        }
                    case .failure(let error):
                        print("[websocket] Error getting anonymous config: \(error)")
                    }
                }
            }
        }
    }
    
    private func receiveFromWebsocket() {
        guard let task = websocketTask else {
            return
        }
        print("[websocket] Listening...")
        
        task.receive { result in
            switch result {
            case .failure(let error):
                print("[websocket] Received error: \(error)")
                self.handleConnectionFailure(for: task)

            case .success(let message):
                switch message {
                case .string(let text):
                    print("[websocket] Received string: \(text)")
                    self.processServerMessage(text)
                case .data(let data):
                    print("[websocket] Received binary: \(data)")
                @unknown default:
                    fatalError()
                }
                
                self.receiveFromWebsocket()
            }
        }
    }
    
    private func processServerMessage(_ message: String) {
        guard let components = try? JSONSerialization.jsonObject(with: message.data(using: .utf8)!) as? [Any] else {
            return
        }
        
        let data = components.count > 1 ? components[1] : nil
        
        if let callbackId = components[0] as? Int, let callback = callbackById[callbackId] {
            let error = components.count > 2 ? components[2] as? [String: String] : nil
            DispatchQueue.main.async {
                callback(data, error)
            }
        } else if let eventName = components[0] as? String, let callback = serverEventCallback {
            DispatchQueue.main.async {
                callback(eventName, data)
            }
        }
    }
    
    public func emit(command: String, data: Any = [String:String](), resultCallback: ((Any?, [String: String]?) -> ())? = nil) {
        guard let jsonData = try? String(data: JSONSerialization.data(withJSONObject: data), encoding: .utf8) else {
            return
        }
        
        DispatchQueue.main.async { [self] in
            var message = "[\"\(command)\",\(jsonData)]"
            if let resultCallback {
                latestCallbackId += 1
                callbackById[latestCallbackId] = resultCallback
                message = "[\"\(command)\",\(jsonData),\(latestCallbackId)]"
            }
            print("[websocket] Sending \(message)")

            let task = websocketTask
            task?.send(URLSessionWebSocketTask.Message.string(message)) { error in
                if let error {
                    print("[websocket] Sending failed: \(error)")
                    self.handleConnectionFailure(for: task)
                    if resultCallback != nil {
                        DispatchQueue.main.async { [self] in
                            callbackById.removeValue(forKey: latestCallbackId)
                        }
                    }
                }
            }
        }
    }
    
    public func closeThenReconnect() {
        DispatchQueue.main.async {
            self.enterReconnecting()
        }
    }

    // MARK: - Reconnection engine

    /// Tears down the current connection and enters (or continues) a reconnect
    /// cycle. Safe to call repeatedly: the first call in a cycle notifies
    /// listeners (so subscribed games are captured for reconnection) and resets
    /// the backoff, subsequent calls just schedule the next attempt. Must be
    /// called on the main queue.
    private func enterReconnecting() {
        let wasReconnecting = isReconnecting

        // Tear down whatever connection or in-flight attempt we currently have.
        connectWatchdog?.cancel()
        connectWatchdog = nil
        pingCancellable?.cancel()
        pingCancellable = nil
        opened = false
        authenticated = false
        websocketTask?.cancel(with: .normalClosure, reason: nil)
        websocketTask = nil

        status = .reconnecting

        if !wasReconnecting {
            isReconnecting = true
            reconnectAttempt = 0
            print("[websocket] Reconnecting...")
            if let callback = serverEventCallback {
                callback("surround/socketClosed", nil)
            }
        }

        scheduleNextConnectionAttempt()
    }

    /// Handles a failure reported by a delegate/completion callback. Callbacks
    /// from tasks we've already replaced are ignored so a single failure never
    /// triggers multiple overlapping reconnects.
    private func handleConnectionFailure(for task: URLSessionTask?) {
        DispatchQueue.main.async {
            if let task, task !== self.websocketTask {
                // Stale callback from a task we've already discarded.
                return
            }
            self.enterReconnecting()
        }
    }

    /// Schedules the next connection attempt using exponential backoff. Cancels
    /// any previously scheduled attempt so there is only ever one in flight.
    private func scheduleNextConnectionAttempt() {
        pendingReconnect?.cancel()

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1
        print("[websocket] Next connection attempt in \(Int(delay))s (attempt \(reconnectAttempt))")

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isReconnecting else {
                return
            }
            self.startNewConnection()
        }
        pendingReconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Creates a fresh session/task and starts connecting, arming a watchdog so
    /// an attempt that hangs without ever opening or erroring still gets
    /// retried. Must be called on the main queue.
    private func startNewConnection() {
        connectWatchdog?.cancel()
        connectWatchdog = nil
        websocketTask?.cancel(with: .normalClosure, reason: nil)

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: websocketDelegateQueue)
        let task = session.webSocketTask(with: websocketURL)
        urlSession = session
        websocketTask = task
        task.resume()
        print("[websocket] Opening connection...")

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            // Only fire if this is still the current, not-yet-opened attempt.
            guard self.websocketTask === task, !self.opened else {
                return
            }
            print("[websocket] Connection attempt timed out")
            self.enterReconnecting()
        }
        connectWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout, execute: watchdog)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { [self] in
            guard webSocketTask === websocketTask else {
                // A previous, superseded attempt opened late — ignore it.
                return
            }

            connectWatchdog?.cancel()
            connectWatchdog = nil
            pendingReconnect?.cancel()
            pendingReconnect = nil
            isReconnecting = false
            reconnectAttempt = 0

            status = .connected
            opened = true
            print("[websocket] Opened")
            receiveFromWebsocket()

            pingCancellable = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { _ in
                self.emit(command: "net/ping", data: ["client": Date().timeIntervalSince1970 * 1000, "drift": self.drift, "latency": self.latency])
            }
            authenticateWebsocket()
            
            for task in onConnectTasks {
                task()
            }
            onConnectTasks = []
            
            if let callback = serverEventCallback {
                callback("surround/socketOpened", nil)
            }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[websocket] Closed with code \(closeCode.rawValue)")
        handleConnectionFailure(for: webSocketTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[websocket] Task completed with error: \(error)")
        }
        handleConnectionFailure(for: task)
    }
}
