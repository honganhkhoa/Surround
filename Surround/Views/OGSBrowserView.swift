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
import SafariServices

func updatedURL(of url: URL, withQuery query: [String: String]) -> URL {
    if query.count == 0 {
        return url
    }
    
    let currentQueryItems = URLComponents(string: url.absoluteString)?.queryItems ?? []
    var newQueryItems = [URLQueryItem]()
    var query = query
    for currentItem in currentQueryItems {
        if let value = query[currentItem.name] {
            newQueryItems.append(URLQueryItem(name: currentItem.name, value: value))
            query.removeValue(forKey: currentItem.name)
        } else {
            newQueryItems.append(currentItem)
        }
    }
    for (key, value) in query {
        newQueryItems.append(URLQueryItem(name: key, value: value))
    }
    if var urlComponents = URLComponents(string: url.absoluteString) {
        urlComponents.queryItems = newQueryItems
        return urlComponents.url ?? url
    }
    return url
}

func firstParam(in url: URL, named name: String) -> String? {
    return URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == name })?.value ?? nil
}

struct OGSBrowserView: View {
    @State var title: String?
    @State var isLoading: Bool = true
    @State var isLoggingIn: Bool = false
    @State var webView: WKWebView?
    var initialURL: URL
    @State var url: URL?
    var showsURLBar = false
    @State var showsGoogleLogin = false
    @State var googleLoginURL: URL? = nil
    @State var requestedURL: URL? = nil
    @State var hasError = false
    @State var googleOAuthCode: String? = nil
    @State var googleOAuthState: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsURLBar {
                Text((url ?? initialURL)?.absoluteString ?? "")
                    .foregroundColor(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray3).cornerRadius(5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
            }
            OGSBrowserWebView(isLoading: $isLoading, isLoggingIn: $isLoggingIn, title: $title, webView: $webView, initialURL: initialURL, url: $url, showsGoogleLogin: $showsGoogleLogin, googleLoginURL: $googleLoginURL, googleOAuthState: $googleOAuthState, requestedURL: requestedURL)
                .opacity(isLoggingIn ? 0 : 1)
        }
//        .navigationBarTitleDisplayMode(.inline)   // Using a different mode than other root views leads to a strange crash on iPad, related to switching sidebar away from NavigationLink
        .navigationBarItems(
            trailing: isLoading || isLoggingIn ?
                AnyView(ProgressView()) :
                AnyView(Button(action: { webView?.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }))
        .navigationTitle(title ?? "")
        .sheet(isPresented: Binding(
            // Using a simple `$showsGoogleLogin` here is not sufficient, as
            // `googleLoginURL` will sometimes be nil if no-one is looking...
            get: { showsGoogleLogin && googleLoginURL != nil },
            set: { showsGoogleLogin = $0 })
        ) {
            SafariView(
                url: googleLoginURL!,
                googleOAuthCode: $googleOAuthCode
            )
        }
        .onChange(of: url) { newURL in
            if newURL?.absoluteString.hasPrefix("\(OGSService.ogsRoot)/login-error") ?? false {
                requestedURL = initialURL
            }
        }
        .onChange(of: googleOAuthCode) { newCode in
            if let code = newCode {
                showsGoogleLogin = false
                if let state = googleOAuthState {
                    if let oauthCompleteURL = URL(string: "\(OGSService.ogsRoot)/complete/google-oauth2/?scope=email+profile+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email+openid+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.profile&authuser=0&prompt=none&state=\(state)&code=\(code)") {
                        requestedURL = oauthCompleteURL
                    }
                }
            }
        }
    }
}

struct OGSBrowserWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    @EnvironmentObject var ogs: OGSService
    @Binding var isLoading: Bool
    @Binding var isLoggingIn: Bool
    @Binding var title: String?
    @Binding var webView: WKWebView?
    var initialURL: URL
    @Binding var url: URL?
    @Binding var showsGoogleLogin: Bool
    @Binding var googleLoginURL: URL?
    @Binding var googleOAuthState: String?
    var requestedURL: URL?
    @State var previousRequestedURL: URL? = nil

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        if ogs.isLoggedIn {
            let script = WKUserScript(
                source: """
var attemptCount = 0;
var check = () => {
    var user = localStorage.getItem('ogs.config.user');
    window.webkit.messageHandlers.ogsLoginHandler.postMessage('checking');
    if (user != null && !JSON.parse(user).anonymous) {
        window.webkit.messageHandlers.ogsLoginHandler.postMessage('done');
        location.reload();
    } else if (attemptCount < 7) {
        attemptCount += 1;
        setTimeout(check, 1000);
    }
}
if (localStorage.getItem('ogs.config.user')==null) {
    setTimeout(check, 1000);
}
""",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(script)
            configuration.userContentController.add(context.coordinator, name: "ogsLoginHandler")
            DispatchQueue.main.async {
                isLoggingIn = true
            }
        }

        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
                
//        if webView.responds(to: Selector(("setInspectable:"))) {
//            webView.perform(Selector(("setInspectable:")), with: true)
//        }

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
        context.coordinator.urlObservation = webView.observe(\.url, options: [.new], changeHandler: { _, change in
            if let newURL = change.newValue {
                if newURL != url {
                    DispatchQueue.main.async {
                        url = newURL
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
        if requestedURL?.absoluteString != previousRequestedURL?.absoluteString {
            DispatchQueue.main.async {
                previousRequestedURL = requestedURL
                if let url = requestedURL {
                    webView?.load(URLRequest(url: url))
                }
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: OGSBrowserWebView
        var loginCancellable: AnyCancellable?
        var loadingObservation: NSKeyValueObservation?
        var titleObservation: NSKeyValueObservation?
        var urlObservation: NSKeyValueObservation?
        var cookiesToSet: [HTTPCookie] = []
        var initialRequestLoaded = false
        var loginAttemptCount = 0
        
        init(_ parent: OGSBrowserWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let message = message.body as? String {
                print("Web view message: " + message)
                if message == "checking" {
                    loginAttemptCount += 1
                }
                if loginAttemptCount > 7 || message == "done" {
                    DispatchQueue.main.async {
                        self.parent.isLoggingIn = false
                    }
                }
            }
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
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            print("---- url: " + (url?.absoluteString ?? ""))
            if let url = url, url.host == "accounts.google.com" {
                decisionHandler(.cancel)
                parent.googleOAuthState = firstParam(in: url, named: "state")
                parent.googleLoginURL = updatedURL(of: url, withQuery: ["state": "stray-request-from-surround-\(Date().timeIntervalSince1970)"])
//                print("---- gg pre login url: " + url.absoluteString)
//                print("---- gg login url: " + (parent.googleLoginURL?.absoluteString ?? "nil"))
                parent.showsGoogleLogin = true
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Binding var googleOAuthCode: String?

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        print("----- sfvc initial: " + url.absoluteString)
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.delegate = context.coordinator
        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var parent: SafariView
        
        init(parent: SafariView) {
            self.parent = parent
        }
        
        func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo url: URL) {
            print("----- sfvc: " + url.absoluteString)
            if url.absoluteString.hasPrefix("\(OGSService.ogsRoot)/complete/google-oauth2") {
                parent.googleOAuthCode = firstParam(in: url, named: "code")
            }
        }
    }
}
