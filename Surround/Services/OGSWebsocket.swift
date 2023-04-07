//
//  OGSWebsocket.swift
//  Surround
//
//  Created by Anh Khoa Hong on 2023/4/6.
//

import Foundation
import Combine

enum OGSWebsocketStatus: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case authenticated
}

class OGSWebsocket: NSObject, URLSessionWebSocketDelegate {
    private var websocketTask: URLSessionWebSocketTask?

    private var latestCallbackId = 0
    private var callbackById: [Int: (Any?, [String: String]?) -> ()] = [:]
    
    public var serverEventCallback: ((String, Any?) -> ())?
    public var onConnectTasks: [() -> ()] = []
    public var onStatusChanged: (() -> ())?

    private var pingCancellable: AnyCancellable?
    private(set) public var authenticated = false
    private(set) public var opened = false
    private(set) public var status = OGSWebsocketStatus.disconnected {
        didSet {
            if let callback = onStatusChanged {
                callback()
            }
        }
    }

    private lazy var jsonEncoder = JSONEncoder()

    public var drift = 0.0
    public var latency = 0.0

    override init() {
        super.init()

        var urlComponents = URLComponents(url: URL(string: OGSService.ogsRoot)!, resolvingAgainstBaseURL: true)
        urlComponents?.scheme = "wss"
        let websocketURL = urlComponents!.url!
        
        let websocketDelegateQueue = OperationQueue()
        websocketDelegateQueue.maxConcurrentOperationCount = 1
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: websocketDelegateQueue)
        websocketTask = urlSession.webSocketTask(with: websocketURL)
        
        websocketTask?.resume()
        status = .connecting
    }
    
    public func authenticateIfLoggedIn() {
        guard let uiConfig = userDefaults[.ogsUIConfig], let jwt = uiConfig.userJwt else {
            return
        }
        
        emit(command: "authenticate", data: ["jwt": jwt])
        emit(command: "automatch/list")
        
        DispatchQueue.main.async {
            self.authenticated = true
            self.status = .authenticated
            if let callback = self.serverEventCallback {
                callback("surround/socketAuthenticated", nil)
            }
        }
    }

    private func receiveFromWebsocket() {
        print("[websocket] Listening...")
        
        websocketTask?.receive { result in
            switch result {
            case .failure(let error):
                print("[websocket] Received error: \(error)")
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

            websocketTask?.send(URLSessionWebSocketTask.Message.string(message)) { error in
                if let error {
                    print("[websocket] Sending failed: \(error)")
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
        status = .reconnecting
        websocketTask?.cancel(with: .normalClosure, reason: nil)
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .seconds(1))) {
            self.websocketTask?.resume()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        status = .connected
        opened = true
        print("[websocket] Opened")
        receiveFromWebsocket()
        DispatchQueue.main.async { [self] in
            pingCancellable = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { _ in
                self.emit(command: "net/ping", data: ["client": Date().timeIntervalSince1970 * 1000, "drift": self.drift, "latency": self.latency])
            }
            authenticateIfLoggedIn()
            
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
        status = .disconnected
        opened = false
        print("[websocket] Closed")

        DispatchQueue.main.async { [self] in
            pingCancellable?.cancel()
            pingCancellable = nil
            authenticated = false
            if let callback = serverEventCallback {
                callback("surround/socketClosed", nil)
            }
        }
    }
}
