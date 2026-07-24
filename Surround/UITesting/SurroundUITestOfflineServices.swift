//
//  SurroundUITestOfflineServices.swift
//  Surround
//
//  Network-rejecting dependencies used only by the deterministic UI-test app.
//

#if DEBUG && MAIN_APP

import Alamofire
import Foundation

final class SurroundUITestRejectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(
                .notConnectedToInternet,
                userInfo: [
                    NSURLErrorFailingURLErrorKey: request.url as Any,
                    NSLocalizedDescriptionKey: "Network access is disabled in Surround UI tests."
                ]
            )
        )
    }

    override func stopLoading() {}
}

final class SurroundUITestRejectingHTTPClient: OGSHTTPClient {
    let session: Session
    let cookieStorage: HTTPCookieStorage?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SurroundUITestRejectingURLProtocol.self]
        configuration.httpCookieStorage = nil
        cookieStorage = nil
        session = Session(configuration: configuration)
    }
}

final class SurroundUITestNoOpWebsocket: OGSWebsocketProtocol {
    var serverEventCallback: ((String, Any?) -> Void)?
    var onConnectTasks: [() -> Void] = []
    var onStatusChanged: (() -> Void)?
    var authenticationConfigProvider: () -> OGSUIConfig? = { nil }

    let authenticated = true
    let opened = true
    let status = OGSWebsocketStatus.connected
    var drift = 0.0
    var latency = 0.0

    func connect() {}
    func close() {}
    func reconnectIfNeeded() {}
    func closeThenReconnect() {}

    func emit(
        command: String,
        data: Any,
        resultCallback: OGSWebsocketResultCallback?
    ) {
        resultCallback?(
            nil,
            [
                "type": "connection",
                "message": "Network access is disabled in Surround UI tests."
            ]
        )
    }
}

#endif
