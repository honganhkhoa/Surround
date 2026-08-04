//
//  SurroundUITestOfflineServices.swift
//  Surround
//
//  Network-rejecting dependencies used only by the deterministic UI-test app.
//

#if DEBUG && MAIN_APP

typealias SurroundUITestRejectingURLProtocol = OGSOfflineRejectingURLProtocol
typealias SurroundUITestRejectingHTTPClient = OGSOfflineRejectingHTTPClient
typealias SurroundUITestNoOpWebsocket = OGSOfflineNoOpWebsocket

#endif
