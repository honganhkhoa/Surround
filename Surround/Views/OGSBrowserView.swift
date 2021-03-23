//
//  OGSBrowserView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/8/20.
//

import SwiftUI
import UIKit
import WebKit
import Alamofire
import Combine

struct OGSBrowserView: View {
    @State var title: String?
    @State var isLoading: Bool = true
    @State var webView: WKWebView?
    var initialURL: URL
    
    var body: some View {
        OGSBrowserWebView(isLoading: $isLoading, title: $title, webView: $webView, initialURL: initialURL)
//            .navigationBarTitleDisplayMode(.inline)   // Using a different mode than other root views leads to a strange crash on iPad, related to switching sidebar away from NavigationLink
            .navigationBarItems(
                trailing: isLoading ?
                    AnyView(ProgressView()) :
                    AnyView(Button(action: { webView?.reload() }) {
                        Image(systemName: "arrow.clockwise")
                    }))
            .navigationTitle(title ?? "")
    }
}

struct OGSBrowserWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    @EnvironmentObject var ogs: OGSService
    @Binding var isLoading: Bool
    @Binding var title: String?
    @Binding var webView: WKWebView?
    var initialURL: URL
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        if UIDevice.current.userInterfaceIdiom == .phone {
            // https://stackoverflow.com/questions/40591090/403-error-thats-an-error-error-disallowed-useragent
            // Google does not allow OAuth in iPhone's WKWebView, so we use Safari's user agent here
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Mobile/15E148 Safari/604.1"
        }
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadingObservation = webView.observe(\.isLoading, options: [.new], changeHandler: { _, change in
            if let newValue = change.newValue {
                if isLoading != newValue {
                    DispatchQueue.main.async {
                        isLoading = newValue
                    }
                }
            }
        })
        context.coordinator.titleObservation = webView.observe(\.title, options: [.new], changeHandler: { _, change in
            if let newTitle = change.newValue {
                if newTitle != title {
                    DispatchQueue.main.async {
                        title = newTitle
                    }
                }
            }
        })

        var request = URLRequest(url: initialURL)
        
        if ogs.ogsUIConfig != nil {
            if let cookies = Session.default.sessionConfiguration.httpCookieStorage?.cookies {
                context.coordinator.cookiesToSet = cookies
                for cookie in cookies {
                    webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
        } else {
            if ogs.isOGSDomain(url: initialURL) && initialURL.pathComponents.last! == "overview" {
                request.url = URL(string: OGSService.ogsRoot)
            }
        }
                        
        if context.coordinator.cookiesToSet.count == 0 {
            context.coordinator.initialRequestLoaded = true
            webView.load(request)
        }
        DispatchQueue.main.async {
            self.webView = webView
            loadInitialRequestIfReadyAndNeeded(request: request, coordinator: context.coordinator)
        }
        return webView
    }
    
    func loadInitialRequestIfReadyAndNeeded(request: URLRequest, coordinator: Coordinator) {
        if coordinator.initialRequestLoaded {
            return
        }
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var matchCount = 0
            for cookie in cookies {
                for cookieToSet in coordinator.cookiesToSet {
                    if cookie.name == cookieToSet.name && cookie.value == cookieToSet.value {
                        matchCount += 1
                    }
                }
            }
            if matchCount == coordinator.cookiesToSet.count {
                coordinator.initialRequestLoaded = true
                webView?.load(request)
            } else {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(1))) {
                    loadInitialRequestIfReadyAndNeeded(request: request, coordinator: coordinator)
                }
            }
        }
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OGSBrowserWebView
        var loginCancellable: AnyCancellable?
        var loadingObservation: NSKeyValueObservation?
        var titleObservation: NSKeyValueObservation?
        var cookiesToSet: [HTTPCookie] = []
        var initialRequestLoaded = false
        
        init(_ parent: OGSBrowserWebView) {
            self.parent = parent
        }
        
        func loginUsingWebviewCredentialsIfNecessary(_ webView: WKWebView) {
            let ogs = parent.ogs
            guard !ogs.isLoggedIn else {
                return
            }

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    if ogs.isOGSDomain(cookie: cookie) && cookie.name == "sessionid" {
                        self.loginCancellable = ogs.thirdPartyLogin(cookieStore: cookieStore)
                            .sink(receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    print(error)
                                }
                            }, receiveValue: { ogsUIConfig in
                                ogs.loadOverview()
                                print(ogsUIConfig)
                            })
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let ogs = parent.ogs
            if let url = webView.url {
                if ogs.isOGSDomain(url: url) {
                    loginUsingWebviewCredentialsIfNecessary(webView)
                }
            }
        }
    }
}
